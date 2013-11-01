package App::Ikaros::Planner;
use strict;
use warnings;
use parent qw/Class::Accessor::Fast/;
use List::Util qw/shuffle/;
use List::MoreUtils qw/part/;
use YAML::XS;
use App::Ikaros::PathMaker;
use Data::Dumper;
use constant {
    PROVE_STATE_FILE => '.prove',
};

__PACKAGE__->mk_accessors(qw/
    prove_tests
    forkprove_tests
    prove_host_num
    forkprove_host_num
    saved_tests
    sorted_tests
/);

sub new {
    my ($class, $hosts, $args) = @_;
    unless ($args->{prove_tests} || $args->{forkprove_tests}) {
        die "must be set 'prove_tests' and 'forkprove_tests(optional)'";
    }
    my $self = $class->SUPER::new({
        %$args,
        prove_host_num     => 0,
        forkprove_host_num => 0,
    });
    $self->load_prove_state([ @{$args->{prove_tests}}, @{$args->{forkprove_tests}} ])
        if (-f PROVE_STATE_FILE);
    $self->setup_testing_cluster($hosts);
    return $self;
}

sub load_prove_state {
    my ($self, $tests) = @_;
    my %tests_map;
    $tests_map{$_}++ foreach @$tests;
    open my $fh, '<', PROVE_STATE_FILE;
    my $code = do { local $/; <$fh> };
    my $yaml = Load $code;
    my $saved_tests = $yaml->{tests};
    my %elapsed_times;
    foreach my $saved_test (keys %$saved_tests) {
        next unless exists $tests_map{$saved_test};
        my $elapsed_time = $saved_tests->{$saved_test}->{elapsed};
        $elapsed_times{$saved_test} = $elapsed_time + 0;
    }
    my @elapsed_times = reverse sort {
        $elapsed_times{$a} <=> $elapsed_times{$b}
    } keys %elapsed_times;
    $self->saved_tests(\%elapsed_times);
    $self->sorted_tests(\@elapsed_times);
}

sub __get_sorted_tests {
    my ($self, $tests) = @_;
    if (defined $self->saved_tests) {
        my %tests_map;
        $tests_map{$_}++ foreach @$tests;
        my @new_tests = shuffle grep { not exists $self->saved_tests->{$_} } @$tests;
        my @sorted_tests = grep { exists $tests_map{$_} } @{$self->sorted_tests};
        return [ @sorted_tests, @new_tests ];
    }
    return [ shuffle @$tests ];
}

sub setup_testing_cluster {
    my ($self, $hosts) = @_;
    foreach my $host (@$hosts) {
        if ($host->runner eq 'prove') {
            $self->{prove_host_num}++;
        } elsif ($host->runner eq 'forkprove') {
            $self->{forkprove_host_num}++;
        } else {
            die "unknown keyword at runner [$host->{runner}]";
        }
    }
    my $prove_tests = $self->__get_sorted_tests($self->prove_tests);
    my $forkprove_tests = $self->__get_sorted_tests($self->forkprove_tests);
    my $host_idx = 0;
    my @prove_tests_clusters = part { $host_idx++ % $self->prove_host_num } @$prove_tests;
    $host_idx = 0;
    my @forkprove_tests_clusters = part { $host_idx++ % $self->forkprove_host_num } @$forkprove_tests;
    foreach my $host (@$hosts) {
        if ($host->runner eq 'prove') {
            $host->tests(shift @prove_tests_clusters);
        } else {
            $host->tests(shift @forkprove_tests_clusters);
        }
    }
}

sub planning {
    my ($self, $host, $args) = @_;
    my $commands = $self->__make_command($args, $host);
    $host->plan($commands);
}

sub __make_command {
    my ($self, $args, $host) = @_;
    my $workdir = $host->workdir;
    my $chdir = "cd $workdir";

    my $lib = "$workdir/ikaros_lib";
    my $bin = "$lib/bin";
    my @coverage = ($host->coverage) ?
        ("-I$lib/lib/perl5", "-MDevel::Cover=-db,cover_db,-coverage,statement,time,+ignore,$lib,local/lib/perl5") : ();

    my @prove_commands = map {
        my $command_part = $_;
        if ($command_part =~ /\$prove/) {
            ("-I$lib", @coverage, "$bin/prove", '--state=save')
        } else {
            $command_part;
        }
    } @{$args->{prove_command}};
    my @forkprove_commands = map {
        my $command_part = $_;
        if ($command_part =~ /\$forkprove/) {
            ("-I$lib", @coverage, "$bin/forkprove", '--state=save')
        } else {
            $command_part;
        }
    } @{$args->{forkprove_command}};

    $host->prove(($host->runner eq 'prove') ? \@prove_commands : \@forkprove_commands);

    my $before_command = $self->__join_command($chdir, $args->{before_commands});
    my $main_command   = $self->__make_main_command($chdir . '/' . $args->{chdir}, $host);
    my $after_command  = $self->__join_command($chdir, $args->{after_commands});

    return [
        "mkdir -p $workdir/ikaros_lib/bin",
        $before_command,
        $main_command,
        $after_command
    ];
}

sub __make_main_command {
    my ($self, $chdir, $host) = @_;

    my $workdir = $host->workdir;
    my $trigger_filename = $host->trigger_filename;
    my $continuous_template = '((%s) || echo 1)';

    my $build_start_flag = "echo 'IKAROS:BUILD_START'";
    my $build_end_flag   = "echo 'IKAROS:BUILD_END'";
    my $move_output    = $self->__move_result_to_dir('junit_output.xml', $workdir);
    my $move_dot_prove = $self->__move_result_to_dir('.prove', $workdir);
    my $move_cover_db  = ($host->coverage) ? $self->__move_result_to_dir('cover_db', $workdir) : 'echo \'skip move cover_db\'';
    my $perl = App::Ikaros::PathMaker::perl($host);
    my $kick_command = sprintf $continuous_template, "$perl -I$workdir/ikaros_lib $workdir/$trigger_filename";
    return join ' && ', (
        $chdir,
        $build_start_flag,
        $kick_command,
        $move_output,
        $move_dot_prove,
        $move_cover_db,
        $build_end_flag
    );
}

sub __move_result_to_dir {
    my ($self, $result, $workdir) = @_;
    return "(if [ -e $result ]; then mv $result $workdir; fi;)";
}

sub __join_command {
    my ($self, $chdir, $commands) = @_;
    my $continuous_template = '((%s) || echo 1)';
    return join ' && ', $chdir, map {
        sprintf $continuous_template, $_;
    } @$commands;
}

1;

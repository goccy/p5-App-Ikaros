package App::Ikaros::Reporter;
use strict;
use warnings;
use parent qw/Class::Accessor::Fast/;
use utf8;
use TAP::Harness::JUnit;
use IPC::Run;
use XML::Simple;
use List::MoreUtils qw/all/;
use Encode qw/encode decode/;
use YAML::XS qw/LoadFile Dump/;
use File::Copy::Recursive qw/rcopy/;
use Data::Dumper;

__PACKAGE__->mk_accessors(qw/
    recovery_testing_command
    output_filename
    verbose
    tests
/);

sub new {
    my ($class, $options) = @_;
    my $reporter = $class->SUPER::new({
        recovery_testing_command => $options->{recovery_testing_command},
        output_filename => $options->{output_filename} || 'ikaros_output.xml',
        verbose  => $options->{verbose} || 0,
        tests    => +{}
    });
    $reporter->__setup_mangled_name_for_junit($options->{tests});
    return $reporter;
}

sub __setup_mangled_name_for_junit {
    my ($self, $tests) = @_;
    foreach my $test_name (@$tests) {
        my $mangled_name = $test_name;
        $mangled_name =~ s/^[\.\/]*//;
        $mangled_name =~ s/-/_/g;
        $mangled_name =~ s/\./_/g;
        $mangled_name =~ s/\//_/g;
        $self->tests->{$mangled_name} = $test_name;
    }
}

sub __setup_testsuites {
    my ($self, $testsuites, $xml_data, $failed) = @_;

    my $testsuite = $xml_data->{testsuite};
    foreach my $test (@$testsuite) {
        my $mangled_name = $test->{name};
        my $name = $self->tests->{$mangled_name};
        unless ($test->{failures} eq '0' && $test->{errors} eq '0') {
            if ($name) {
                $failed->{$name}++;
            } else {
                warn "nothing include $mangled_name";
            }
        } else {
            #$test->{testcase} = [];
        }
        $testsuites->{$name} = $test if ($name);
    }
}

sub __setup_dot_prove {
    my ($self, $host, $dot_prove) = @_;

    my $loaded_data = LoadFile $host->dot_prove_filename;
    $dot_prove->{last_run_time} = $loaded_data->{last_run_time};
    $dot_prove->{generation} = $loaded_data->{generation};
    $dot_prove->{version} = $loaded_data->{version};
    $dot_prove->{tests}{$_} = $loaded_data->{tests}{$_} foreach keys %{$loaded_data->{tests}};
}

sub report {
    my ($self, $hosts) = @_;
    my (%testsuites, %failed, %dot_prove, %cover_db);
    my $verbose = $self->verbose;

    foreach my $host (@$hosts) {
        next unless ($host->tests);
        $self->__recv_report($host);
        next unless (defined $host->output_filename && -f $host->output_filename);
        my $xml_data = $self->__load_xml_data($host->output_filename);
        next unless (defined $xml_data);

        $self->__setup_testsuites(\%testsuites, $xml_data, \%failed);
        $self->__setup_dot_prove($host, \%dot_prove);

        $cover_db{$host->cover_db_name}++ if ($host->coverage);
        unlink $host->output_filename;
        unlink $host->dot_prove_filename;
    }

    my $prove_command_line = $self->recovery_testing_command;
    my @failed_tests = keys %failed;

    if (@failed_tests) {
        my $num = scalar @failed_tests;
        print "retest $num tests.\n";
        my @failed_tests_at_retry = $self->__retest(@$prove_command_line, @failed_tests);
        $self->__remove_failures_by_result_of_retry(\%testsuites, \@failed_tests, \@failed_tests_at_retry);
        @failed_tests = @failed_tests_at_retry;
    }

    $self->__generate_result(\%testsuites);
    $self->__generate_dot_prove(\%dot_prove);
    $self->__generate_coverage(\%cover_db);
    return \@failed_tests;
}

sub __load_xml_data {
    my ($self, $filename) = @_;
    my $source = $self->__slurp($filename);
    $source =~ s|<system-out>(.*?)</system-out>|<system-out></system-out>|smg;
    $XML::Simple::PREFERRED_PARSER = 'XML::Parser';
    my $xml = XML::Simple->new(ForceArray => 1, KeyAttr => ['partnum']);
    my $xml_data;
    local $@;
    eval { $xml_data = $xml->XMLin($source); };
    if ($@) {
        warn "[ERROR]: Cannot load from $filename. $@";
        return undef;
    }
    return $xml_data;
}

sub __remove_failures_by_result_of_retry {
    my ($self, $testsuites, $failed_tests, $failed_tests_at_retry) = @_;
    foreach my $test_name (@$failed_tests) {
        if (all { $test_name ne $_ } @$failed_tests_at_retry) {
            my $test = $testsuites->{$test_name};
            $test->{failures} = '0';
            $test->{errors} = '0';
            my $testcases = $test->{testcase};
            delete $_->{failure} foreach grep { $_->{failure} } @$testcases;
        }
    }
}

sub __generate_result {
    my ($self, $testsuites) = @_;
    my $result = +{
        testsuite => [ values %$testsuites ]
    };
    my $xml = XML::Simple->new()->XMLout($result, RootName => 'testsuites');
    open my $xml_fh, '>', $self->output_filename;
    print $xml_fh "<?xml version='1.0' encoding='utf-8'?>\n";
    print $xml_fh $xml;
    close $xml_fh;
}

sub __generate_dot_prove {
    my ($self, $merged_dot_prove) = @_;
    my $dot_prove = '.prove';
    open my $fh, '>', $dot_prove;
    print $fh Dump $merged_dot_prove;
    print $fh "...\n\n";
    close $fh;
}

sub __generate_coverage {
    my ($self, $cover_db) = @_;
    rcopy($_, 'merged_db') foreach (keys %$cover_db);
}

sub __retest {
    my ($self, @argv) = @_;
    my $stdout = '';
    my $status = do {
        my $in = '';
        my $out = sub {
            my ($s) = @_;
            $stdout .= $s;
            print $s;
        };
        my $err = sub { print shift };
        IPC::Run::run \@argv, \$in, $out, $err;
    };

    return map {
        if ($_ =~ /\A(.*?)\s*\(Wstat: [1-9]/ms) {
            $1;
        } else {
            ();
        }
    } split /\n/xms, $stdout;
}

sub __slurp {
    my ($self, $filename) = @_;
    open my $fh, '<', $filename;
    return do { local $/; <$fh> };
}

sub __recv_report {
    my ($self, $host) = @_;
    print "fetch from " . $host->hostname, "\n";
    $host->connection->scp_get({}, $host->workdir . '/junit_output.xml', $host->output_filename);
    $host->connection->scp_get({}, $host->workdir . '/.prove', $host->dot_prove_filename);
    $host->connection->scp_get({
        recursive => 1,
    }, $host->workdir . '/cover_db', $host->cover_db_name) if ($host->coverage);
}

1;

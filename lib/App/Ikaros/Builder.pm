package App::Ikaros::Builder;
use strict;
use warnings;
use parent qw/Class::Accessor::Fast/;
use Coro;
use Coro::Select;
use Capture::Tiny ':all';
use constant {
    DEBUG => 0
};
use App::Ikaros::Logger;
use App::Ikaros::PathMaker qw/
    lib_top_dir
    prove
    forkprove
/;

__PACKAGE__->mk_accessors(qw/
    logger
    code
/);

sub new {
    my ($class) = @_;
    my $code = do { local $/; <DATA> };
    return $class->SUPER::new({
        logger => App::Ikaros::Logger->new,
        code   => $code
    });
}

sub build {
    my ($self, $hosts) = @_;
    my @coros;
    foreach my $host (@$hosts) {
        push @coros, async { $self->__run($host); };
    }
    $_->join foreach @coros;
}

sub __run {
    my ($self, $host) = @_;
    if (DEBUG) {
        my $num = (ref $host->tests eq 'ARRAY') ? scalar @{$host->tests} : 0;
        print $host->hostname . ' : ' . $num, "\n";
    }
    return unless defined $host->tests;

    my $filename = $host->trigger_filename;
    my $plan = $host->plan;
    my $mkdir = shift @$plan;

    $self->__run_command_at_remote($host, $mkdir);
    $self->__send_libraries($host);
    $self->__install_devel_cover($host) if ($host->coverage);
    $self->__send_trigger_file($host);
    $self->__run_command_at_remote($host, $_) foreach (@$plan);

    unlink $host->trigger_filename;
}

sub __run_command_at_remote {
    my ($self, $host, $command) = @_;
    my ($stdin, $stdout, $stderr, $pid) = $host->connection->open3({}, $command);
    die 'undefined stdout handle' unless (defined $stdout);
    $self->logger->add($host->hostname, $stdout, $stderr);
    $self->logger->logging($host->hostname, $pid);
    waitpid($pid, 0);
}

sub __send_libraries {
    my ($self, $target) = @_;

    my @libs;
    my @bins = (prove, forkprove);

    foreach my $class (qw{
        App/Prove.pm
        App/ForkProve.pm
        XML/Simple.pm
        TAP/Harness/JUnit.pm
        IPC/Run.pm}) {
        my $lib_top_dir = lib_top_dir $class;
        push @libs, $lib_top_dir if (-d $lib_top_dir);
    }

    my $workdir = $target->workdir;
    $target->connection->rsync_put({
        recursive => 1,
    }, $_, $workdir . '/ikaros_lib/') foreach (@libs);

    $target->connection->rsync_put({
        recursive => 1,
    }, $_, $workdir . '/ikaros_lib/bin/') foreach (@bins);
}

sub __install_devel_cover {
    my ($self, $host) = @_;
    my $workdir = $host->workdir;
    my $env = ($host->perlbrew) ? 'source $HOME/perl5/perlbrew/etc/bashrc;' : '';
    my $cpanm = "$env cd $workdir && curl -LO http://xrl.us/cpanm";
    my $install_devel_cover = "$env cd $workdir && perl cpanm -l ikaros_lib Devel::Cover --notest";

    $self->__run_command_at_remote($host, $cpanm);
    $self->__run_command_at_remote($host, $install_devel_cover);
}

sub __send_trigger_file {
    my ($self, $host) = @_;
    return unless defined $host->tests;
    my $filename = $host->trigger_filename;
    my $tests = join ', ', map { "'$_'" } @{$host->tests};
    my $prove = join ', ', map { "'$_'" } @{$host->prove};
    my $trigger_script = sprintf($self->code, $prove, $tests);
    open my $fh, '>', $filename;
    print $fh $trigger_script;
    close $fh;
    $host->connection->scp_put({}, $filename, $host->workdir);
}

1;

__DATA__
use strict;
use warnings;
use IPC::Run qw//;

sub run {
    my (@argv) = @_;
    my $stdout = '';
    my $status = do {
        my $in = '';
        my $out = sub {
            my ($s) = @_;
            $stdout .= $s;
            print $s;
        };
        my $err = sub { warn shift; };
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

my @prove_args = (
    %s,
    '--harness',
    'TAP::Harness::JUnit',
    %s
);
run(@prove_args);
exit(1);

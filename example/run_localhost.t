use strict;
use warnings;
use Test::More;
use App::Ikaros;
use File::Temp qw//;
use IO::Handle;
use Net::OpenSSH;

plan skip_all =>  "SSH client not found"
    unless `ssh -V 2>&1`;

my $ssh = Net::OpenSSH->new(
    host => 'localhost',
    timeout => 15,
    strict_mode => 0,
);
plan skip_all => 'Unable to establish SSH connection to localhost!'
    if $ssh->error;


my $DEFAULT_DIR = File::Temp->newdir();
my $OVERRIDE_DIR1 = File::Temp->newdir( CLEANUP => 1 );
my $OVERRIDE_DIR2 = File::Temp->newdir( CLEANUP => 1 );
my $APP_DIR = 'app';
my $conf_fh = File::Temp->new( UNLINK => 1, SUFFIX => '.yaml' );
$conf_fh->autoflush(1);
$conf_fh->print(<<"END");
default:
  runner: prove
  workdir: $DEFAULT_DIR
  plenv: true
  ssh_opt:
    strict_mode: 0

hosts:
  - localhost:
      runner: prove
      workdir: $OVERRIDE_DIR1

  - localhost:
      runner: prove
      workdir: $OVERRIDE_DIR2

plan:
  chdir: $APP_DIR
  prove_tests:
    - example/plan/test1.plan
    - example/plan/test2.plan
  prove_command:
    - perl
    # preload TAP::Harness due to bug of Base.pm (version 2.16)
    - -MTAP::Harness
    - \$prove
  rsync:
    to: $APP_DIR
    opt:
      - -az
      - --exclude='.git'
END

my $status = App::Ikaros->new({
    config  => $conf_fh->filename,
})->launch(sub {
     my @failed_tests = @{+shift || []};
     print 'failed_tests: ', scalar @failed_tests, "\n";
 });
pass('ikaros done');

done_testing;


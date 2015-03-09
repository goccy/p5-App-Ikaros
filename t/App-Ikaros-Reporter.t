use strict;
use warnings;
use Test::More;
use App::Ikaros::Reporter;

BEGIN { use_ok 'App::Ikaros::Reporter' }

subtest 'parse_failed_tests_from_output' => sub {

    subtest 'empty' => sub {
        ok !App::Ikaros::Reporter->parse_failed_tests_from_output("");
    };

    subtest 'Multiple tests' => sub {
        my @failed = App::Ikaros::Reporter->parse_failed_tests_from_output(<<OUTPUT);
t/test1.t                                                       (Wstat: 256 Tests: 7 Failed: 0)
  Failed test:  6
t/test2.t                                                        (Wstat: 0 Tests: 3 Failed: 1)
  Failed test:  3

OUTPUT
        is_deeply \@failed, [ qw(
            t/test1.t
            t/test2.t
        ) ];
    };

    subtest 'Wstat:0 Failed:>0' => sub {
        my @failed = App::Ikaros::Reporter->parse_failed_tests_from_output(<<OUTPUT);
t/test1.t                                                       (Wstat: 0 Tests: 7 Failed: 1)
  Failed test:  6
OUTPUT
        is_deeply \@failed, [ 't/test1.t' ];
    };

    subtest 'Wstat:>0 Failed:0' => sub {
        my @failed = App::Ikaros::Reporter->parse_failed_tests_from_output(<<OUTPUT);
t/test1.t                                                       (Wstat: 256 Tests: 7 Failed: 0)
  Failed test:  6
OUTPUT
        is_deeply \@failed, [ 't/test1.t' ];
    };
};

done_testing;

use strict;
use warnings;
use Test::More;
use App::Ikaros::Planner;

my $plan = {
    prove_tests    => [ 'test.t' ],
    prove_command  => ['$prove' ]
};

my $planner = App::Ikaros::Planner->new($plan);

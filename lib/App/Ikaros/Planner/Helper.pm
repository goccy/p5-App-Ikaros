package App::Ikaros::Planner::Helper;
use strict;
use warnings;
use YAML::XS;
use base 'Exporter';

our @EXPORT = qw/
    exclude_blacklist
    load_tests_from_yaml
/;

sub exclude_blacklist {
    my ($all_tests, $blacklist) = @_;
    my %tests;
    $tests{$_}++ foreach @$blacklist;
    return [ grep { not exists $tests{$_} } @$all_tests ];
}

sub load_tests_from_yaml {
    my ($filename) = @_;
    return Load $filename;
}

1;

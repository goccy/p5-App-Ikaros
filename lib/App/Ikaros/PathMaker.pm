package App::Ikaros::PathMaker;
use strict;
use warnings;
use File::Basename qw/dirname/;
use base 'Exporter';

our @EXPORT_OK = qw/
    perl
    lib
    lib_top_dir
    parent_lib_dir
    perl5_dir
    lib_dir
    bin_dir
/;

sub perl($) {
    my ($host) = @_;
    my $env = ($host->perlbrew) ? 'source $HOME/perl5/perlbrew/etc/bashrc;' : '';
    return $env . 'perl';
}

sub lib($) {
    my $class = shift;
    require $class;
    return dirname $INC{$class};
}

sub lib_top_dir($) {
    my $class = shift;
    my $parent_lib_dir = parent_lib_dir($class);
    return ($parent_lib_dir) ?
        perl5_dir($class) . '/' . $parent_lib_dir : lib $class;
}

sub parent_lib_dir($) {
    my $class = shift;
    my ($lib_dir) = lib($class) =~ m|perl5/(.*)|;
    my ($parent_lib_dir) = $lib_dir =~ m|(.*)/|;
    return $parent_lib_dir;
}

sub lib_dir($) {
    my $class = shift;
    my ($lib_dir) = lib($class) =~ m|(.*)/perl5/|;
    return $lib_dir;
}

sub bin_dir($) {
    my $class = shift;
    my ($root) = lib($class) =~ m|(.*)/lib/perl5/|;
    return $root . '/bin';
}

sub perl5_dir($) {
    my $class = shift;
    return lib_dir($class) . '/perl5';
}

1;

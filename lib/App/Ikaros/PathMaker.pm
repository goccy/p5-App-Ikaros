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
    my $lib = lib($class);
    my @dirs = grep { $_ ne '' } split '/', $lib;
    my @parent_dirs;
    @parent_dirs = grep { $_ ne '' } split '/', $class;
    my $depth = scalar @parent_dirs;
    my $size = scalar @dirs;
    return '/' . join '/', @dirs[0 .. $size - ($depth-1)];
}

sub parent_lib_dir($) {
    my $class = shift;
    my @parent_dirs = grep { $_ ne '' } split '/', $class;
    my $depth = scalar @parent_dirs;
    return ($depth > 0) ? $parent_dirs[0] : '';
}

sub lib_dir($) {
    my $class = shift;
    my $lib = lib($class);
    my @dirs = grep { $_ ne '' } split '/', $lib;
    my @parent_dirs;
    @parent_dirs = grep { $_ ne '' } split '/', $class;
    my $depth = scalar @parent_dirs;
    my $size = scalar @dirs;
    return '/' . join('/', @dirs[0 .. $size - ($depth+1)]) . '/bin';
}

sub bin_dir($) {
    my $class = shift;
    my $lib = lib($class);
    my @dirs = grep { $_ ne '' } split '/', $lib;
    my @parent_dirs;
    @parent_dirs = grep { $_ ne '' } split '/', $class;
    my $depth = scalar @parent_dirs;
    my $size = scalar @dirs;
    return '/' . join('/', @dirs[0 .. $size - ($depth+2)]) . '/bin';
}

sub perl5_dir($) {
    my $class = shift;
    return lib_dir($class) . '/perl5';
}

1;

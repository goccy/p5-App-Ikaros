package App::Ikaros;
use 5.008_001;
use strict;
use warnings;
use parent qw/Class::Accessor::Fast/;
use Getopt::Long;
use File::Basename qw/dirname/;
use Data::Dumper;
use App::Ikaros::Config::Loader;
use App::Ikaros::Planner;
use App::Ikaros::LandingPoint;
use App::Ikaros::Builder;
use App::Ikaros::Reporter;

our $VERSION = '0.01';

__PACKAGE__->mk_accessors(qw/
    hosts
    config
    tests
    options
    prove
/);

sub new {
    my ($class, @args) = @_;

    my $self = {};
    local @ARGV = @args;
    my $parser = Getopt::Long::Parser->new(
        config => ["no_ignore_case", "pass_through"],
    );
    $parser->getoptions(
        'h|help'     => \$self->{help},
        'c|config=s' => \$self->{config},
        'config_load_engine=s' => \$self->{config_load_engine},
    );
    return usage() if ($self->{help});

    my $loaded_conf = App::Ikaros::Config::Loader->new({
        engine => $self->{config_load_engine},
        config => $self->{config},
    })->load;

    my $ikaros = $class->SUPER::new({
        config   => $loaded_conf,
        hosts    => []
    });

    $ikaros->__setup_landing_points;
    return $ikaros;
}

sub usage {

}

sub __setup_landing_points {
    my ($self) = @_;
    my $default = $self->config->{default};
    foreach my $host (@{$self->config->{hosts}}) {
        push @{$self->hosts}, App::Ikaros::LandingPoint->new($default, $host);
    }
}

sub plan {
    my ($self, $args) = @_;
    my $planner = App::Ikaros::Planner->new($self->hosts, $args);
    $planner->planning($_, $args) foreach @{$self->hosts};
    $self->tests([ @{$args->{prove_tests}}, @{$args->{forkprove_tests}} ]);
    $self->__setup_recovery_testing_command($args);
}

sub __setup_recovery_testing_command {
    my ($self, $args) = @_;
    my $class = 'App/Prove.pm';
    require $class;
    my $path = $INC{$class};
    my $dirname = dirname $path;
    my ($libdir) = $dirname =~ m|(.*)/perl5/|;
    my ($rootdir) = $dirname =~ m|(.*)/lib/perl5/|;
    my $prove = "$rootdir/bin/prove";
    $self->prove(['perl', "-I$libdir", $prove, @{$args->{prove_command_args}}]);
}

sub launch {
    my ($self, $callback) = @_;
    my $builder = App::Ikaros::Builder->new;
    $builder->build($self->hosts);
    my $reporter = App::Ikaros::Reporter->new($self->options, $self->tests);
    $reporter->recovery_testing_command($self->prove);
    my $failed_tests = $reporter->report($self->hosts);
    return &$callback($failed_tests);
}

1;

__END__

=head1 NAME

App::Ikaros - distributed testing framework for jenkins

=head1 SYNOPSIS

    use App::Ikaros;

=head1 DESCRIPTION

App::Ikaros

=head1 METHODS

=head1 AUTHOR

Masaaki Goshima (goccy) <goccy54@gmail.com>

=head1 COPYRIGHT AND LICENSE

Copyright (C) Masaaki Goshima (goccy).

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

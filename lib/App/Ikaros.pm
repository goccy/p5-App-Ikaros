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
use App::Ikaros::PathMaker qw/bin_dir lib_dir/;

our $VERSION = '0.01';

__PACKAGE__->mk_accessors(qw/
    hosts
    config
    tests
    options
    prove
/);

sub new {
    my ($class, $options) = @_;

    my $loaded_conf = App::Ikaros::Config::Loader->new({
        config => $options->{config},
        config_type => $options->{config_type},
        config_options => $options->{config_options}
    })->load;

    my $ikaros = $class->SUPER::new({
        config   => $loaded_conf,
        hosts    => []
    });

    $ikaros->__setup_landing_points;
    $ikaros->__planning;
    return $ikaros;
}

sub __setup_landing_points {
    my ($self) = @_;
    my $default = $self->config->{default};
    foreach my $host (@{$self->config->{hosts}}) {
        push @{$self->hosts}, App::Ikaros::LandingPoint->new($default, $host);
    }
}

sub __planning {
    my ($self) = @_;
    my $plan = $self->config->{plan};
    my $planner = App::Ikaros::Planner->new($self->hosts, $plan);
    $planner->planning($_, $plan) foreach @{$self->hosts};
    $self->tests([ @{$plan->{prove_tests}}, @{$plan->{forkprove_tests}} ]);
    $self->__setup_recovery_testing_command($plan);
}

sub __setup_recovery_testing_command {
    my ($self, $args) = @_;
    my $bin = bin_dir 'App/Prove.pm';
    my $lib = lib_dir 'App/Prove.pm';
    my @prove_commands = map {
        my $command_part = $_;
        if ($command_part =~ /\$prove/) {
            ("-I$lib", "$bin/prove")
        } else {
            $command_part;
        }
    } @{$args->{prove_command}};
    $self->prove(\@prove_commands);
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

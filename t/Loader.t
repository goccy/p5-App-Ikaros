use strict;
use warnings;
use Test::More;
use App::Ikaros::Config::Loader;

subtest 'load YAML' => sub {
    my %options = (
        config => 't/var/config_ikaros.yaml',
        config_type => 'yaml',
    ); 

    my $loader = App::Ikaros::Config::Loader->new({
        config         => $options{config},
        config_type    => $options{config_type},
    });
    is(ref $loader->{engine}, 'App::Ikaros::Config::Loader::Engine::YAML');
    ok($loader->load);

    my $loader2 = App::Ikaros::Config::Loader->new({ config  => $options{config} });
    is(ref $loader2->{engine}, 'App::Ikaros::Config::Loader::Engine::YAML');
    

};

subtest 'load DSL' => sub {
    my $loader = App::Ikaros::Config::Loader->new({
        config         => 't/var/config_ikaros.dsl',
        config_type    => 'dsl',
        config_options => {},
    });

    is(ref $loader->{engine}, 'App::Ikaros::Config::Loader::Engine::DSL');
    ok($loader->load);
};

done_testing;

use Mojo::Base -strict;
use Test::More;
use Mojo::Server::Hypnotoad;

my $h = new_ok('Mojo::Server::Hypnotoad');
$h->with_roles('+Launchd');
ok $h->does('Mojo::Server::Hypnotoad::Role::Launchd'), 'composed';

eval {
    $h->daemonize;
};
like $@, qr/^Not allowed/, 'method installed';

my $pf = $h->prefork;
ok $pf->does('Mojo::Server::Prefork::Role::Launchd'), 'composed';

my $morbo_poll = $pf->backend;
ok $morbo_poll->does('Mojo::Server::Morbo::Backend::Poll::Role::CacheUpdate'),
    'backend updates cache - checks unlinked files';

# configure
{
    my $hypnotoad = Mojo::Server::Hypnotoad->with_roles('+Launchd')->new;
    $hypnotoad->prefork->app->config->{myserver} = {
        accepts            => 13,
        backlog            => 43,
        clients            => 1e4,
        graceful_timeout   => 23,
        heartbeat_interval => 7,
        heartbeat_timeout  => 9,
        inactivity_timeout => 5,
        listen             => ['http://*:8081'],
        pid_file           => '/foo/bar.pid',
        proxy              => 1,
        requests           => 3,
        spare              => 4,
        upgrade_timeout    => 45,
        workers            => 7
    };
    $hypnotoad->configure('test');
    is_deeply $hypnotoad->prefork->listen, [], 'default value';
    $hypnotoad->configure('myserver');
    is_deeply $hypnotoad->prefork->listen, [],
        'must be overridden for plugin Config => {}';
    is $hypnotoad->prefork->max_clients, 0, 'no client please';
}

done_testing;

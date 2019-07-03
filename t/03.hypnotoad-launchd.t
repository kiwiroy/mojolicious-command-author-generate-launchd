use Mojo::Base -strict;
use Mojo::File qw{tempdir};
use Mojo::UserAgent;
use Test::More;
use FindBin;
use Mojo::Server::Hypnotoad;

#
# This is repurposed version of t/mojo/hypnotoad.t
#
plan skip_all => 'set TEST_HYPNOTOAD to enable this test (developer only!)'
  unless $ENV{TEST_HYPNOTOAD} || $ENV{TEST_ALL};

# Prepare script
my $dir    = tempdir;
my $script = $dir->child('myapp.pl');
my $log    = $dir->child('mojo.log');
my $launch = $dir->child('launchd.log');
my $port1  = Mojo::IOLoop::Server->generate_port;
my $port2  = Mojo::IOLoop::Server->generate_port;
$script->spurt(<<EOF);
use Mojolicious::Lite;
use Mojo::IOLoop;
app->log->path('$log');
plugin Config => {
default => {
  hypnotoad => {
    listen => ['http://127.0.0.1:$port1', 'http://127.0.0.1:$port2'],
    workers => 1
  }
}
};
app->log->level('debug');
get '/hello' => {text => 'Hello Hypnotoad!'};
my \$graceful;
Mojo::IOLoop->singleton->on(finish => sub { \$graceful++ });
get '/graceful' => sub {
my \$c = shift;
my \$id;
\$id = Mojo::IOLoop->recurring(0 => sub {
  return unless \$graceful;
  \$c->render(text => 'Graceful shutdown!');
  Mojo::IOLoop->remove(\$id);
});
};
app->start;
EOF

# Start
my $prefix = "$FindBin::Bin/../script";
my $pid = open my $start, '-|', $^X, "$prefix/hypnotoad-launchd", $script;
ok $pid;
sleep 3;
sleep 1 while !_port($port2);

# Application is alive
my $ua = Mojo::UserAgent->new;
my $tx = $ua->get("http://127.0.0.1:$port1/hello");
ok $tx->is_finished, 'transaction is finished';
ok $tx->keep_alive,  'connection will be kept alive';
ok !$tx->kept_alive, 'connection was not kept alive';
is $tx->res->code, 200, 'right status';
is $tx->res->body, 'Hello Hypnotoad!', 'right content';

# Application is alive (second port)
$tx = $ua->get("http://127.0.0.1:$port2/hello");
ok $tx->is_finished, 'transaction is finished';
ok $tx->keep_alive,  'connection will be kept alive';
ok !$tx->kept_alive, 'connection was not kept alive';
is $tx->res->code, 200, 'right status';
is $tx->res->body, 'Hello Hypnotoad!', 'right content';

# Update script (broken)
$script->spurt(<<'EOF');
use Mojolicious::Lite;

die if $ENV{HYPNOTOAD_PID};

app->start;
EOF

# send signal - checks proxying
ok kill 'USR2', $pid;

# Wait for hot deployment to fail
while (1) {
  last if $log->slurp =~ qr/Zero downtime software upgrade failed/;
  sleep 1;
}

# Connection did not get lost
$tx = $ua->get("http://127.0.0.1:$port1/hello");
ok $tx->is_finished, 'transaction is finished';
ok $tx->keep_alive,  'connection will be kept alive';
ok $tx->kept_alive,  'connection was kept alive';
is $tx->res->code, 200, 'right status';
is $tx->res->body, 'Hello Hypnotoad!', 'right content';

# Connection did not get lost (second port)
$tx = $ua->get("http://127.0.0.1:$port2/hello");
ok $tx->is_finished, 'transaction is finished';
ok $tx->keep_alive,  'connection will be kept alive';
ok $tx->kept_alive,  'connection was kept alive';
is $tx->res->code, 200, 'right status';
is $tx->res->body, 'Hello Hypnotoad!', 'right content';

# Update script
$script->spurt(<<EOF);
use Mojolicious::Lite;
app->log->path('$log');
plugin Config => {
  default => {
    hypnotoad => {
      accepts => 2,
      inactivity_timeout => 3,
      listen => ['http://127.0.0.1:$port1', 'http://127.0.0.1:$port2'],
      requests => 1,
      workers => 1
    }
  }
};
app->log->level('debug');
get '/hello' => sub { shift->render(text => "Hello World \$\$!") };
app->start;
EOF

# send signal - proxying again
ok kill 'USR2', $pid;

# Wait for hot deployment to succeed
while (1) {
  last if $log->slurp =~ qr/Upgrade successful/;
  sleep 1;
}


# One uncertain request that may or may not be served by the old worker
$tx = $ua->get("http://127.0.0.1:$port1/hello");
is $tx->res->code, 200, 'right status';
$tx = $ua->get("http://127.0.0.1:$port2/hello");
is $tx->res->code, 200, 'right status';

# Application has been reloaded
$tx = $ua->get("http://127.0.0.1:$port1/hello");
ok $tx->is_finished, 'transaction is finished';
ok !$tx->keep_alive, 'connection will not be kept alive';
ok !$tx->kept_alive, 'connection was not kept alive';
is $tx->res->code, 200, 'right status';
my $first = $tx->res->body;
like $first, qr/Hello World \d+!/, 'right content';

# Application has been reloaded (second port)
$tx = $ua->get("http://127.0.0.1:$port1/hello");
ok $tx->is_finished, 'transaction is finished';
ok !$tx->keep_alive, 'connection will not be kept alive';
ok !$tx->kept_alive, 'connection was not kept alive';
is $tx->res->code, 200, 'right status';
is $tx->res->body, $first, 'same content';

# shutdown hypnotoad daemon - subvert controller - it should exit too as it notices
my $hpid = _pid();
ok defined $hpid;
ok $pid != 0;
# send signal
ok kill 'TERM', $hpid;
sleep 1 while _port($port2);

sleep 1 while -f $dir->child('hypnotoad.pid');
sleep 1;

like $launch->slurp, qr/This is the end/, 'finished';

# close everything
ok close $start;

ok !kill 0, $pid;

# run again
$pid = open my $start_again, '-|', $^X, "$prefix/hypnotoad-launchd", $script;
ok $pid;
sleep 3;
sleep 1 while !_port($port2);

# Application has been reloaded
$tx = $ua->get("http://127.0.0.1:$port1/hello");
ok $tx->is_finished, 'transaction is finished';
ok !$tx->keep_alive, 'connection will not be kept alive';
ok !$tx->kept_alive, 'connection was not kept alive';
is $tx->res->code, 200, 'right status';
$first = $tx->res->body;
like $first, qr/Hello World \d+!/, 'right content';

# Application has been reloaded (second port)
$tx = $ua->get("http://127.0.0.1:$port2/hello");
ok $tx->is_finished, 'transaction is finished';
ok !$tx->keep_alive, 'connection will not be kept alive';
ok !$tx->kept_alive, 'connection was not kept alive';
is $tx->res->code, 200, 'right status';
$first = $tx->res->body;
like $first, qr/Hello World \d+!/, 'right content';

$hpid = _pid();
ok defined $hpid;
ok $hpid != 0;
# signal controller to shutdown - launchd will do this
ok kill 'TERM', $pid;
# wait until hypnotoad has also shutdown
sleep 1 while _port($port2);
sleep 1;
# close filehandle to avoid waiting.
ok close $start_again;

# make sure
ok !kill 0, $pid;
ok !kill 0, $hpid;

is _pid(), undef, 'pid file removed';

sub _pid {
    return undef unless -f $dir->child('hypnotoad.pid');
    my ($pid) = (split $/ => $dir->child('hypnotoad.pid')->slurp);
    return 0 unless $pid && kill 0, $pid;
    return $pid;
}

sub _port { IO::Socket::INET->new(PeerAddr => '127.0.0.1', PeerPort => shift) }

done_testing;

use Mojo::Base -strict;
use Mojo::File qw{path tempdir};
use Test::More;
use Mojo::Server::Prefork;
use Mojo::Server::Hypnotoad;

# helpful transformation of modified_files for consistent tests
sub simplify_modified {
  my $modified = shift;
  # sort on basename of file
  return [
    sort { $a->[0] cmp $b->[0] }
    map  { [ path($_->[0])->basename, $_->[1] ] } @$modified];
}

# Create the prefork server instance
my $prefork = Mojo::Server::Prefork->with_roles('+Launchd')->new;
my $backend = $prefork->backend;
ok $backend;

# Temporary directory to hold files to watch
my $dir = tempdir 'morbo-backend-test.XXXXX', TMPDIR => 1;
# Initialise the watching
$backend->watch([$dir]);
my $modified = $backend->modified_files;
$dir->child('foo')->spurt('bar');
$dir->child('bar')->spurt('foo');
$dir->child('hypnotoad.pid')->spurt($$);

# check watching
$modified = simplify_modified $backend->modified_files;
is_deeply $modified, [
  ['bar', 'MODIFIED'], ['foo', 'MODIFIED'], ['hypnotoad.pid', 'MODIFIED']],
  'new files';

# another check
$dir->child('morbo')->spurt('ok');
$modified = simplify_modified $backend->modified_files;
is_deeply $modified, [['morbo', 'MODIFIED']], 'morbo';

# check the role catches unlinking
$dir->child('foo')->remove;
$modified = simplify_modified $backend->modified_files;
is_deeply $modified, [['foo', 'UNLINKED']], 'foo removed';

# Test the prefork server a little more - including internal methods.
eval { $prefork->_listen };
is $@->message, 'Prefork Launchd must not listen', '_listen throws - msg ok';
my $wait = 0;
$prefork->_add_watch($dir);
$prefork->app->log->path($dir->child('test.log'));
$prefork->_modify_log;
$prefork->app->config->{hypnotoad}{pid_file} = $dir->child('hypnotoad.pid');
$prefork->{finished} = 1; # important
$prefork->on(wait => sub {
  $dir->child('foo')->spurt('bar');
  $dir->child('hypnotoad.pid')->remove;
  $wait++
});
$prefork->run;
is $wait, 2, 'ran and _managed';

# stopping removes pid from pool
$prefork->{pool}{$prefork->{hypnotoad} = 200}{time} = Mojo::Util::steady_time;
$prefork->_stopped($prefork->{hypnotoad});
is_deeply [keys %{$prefork->{pool}}], [], 'removed';

# hypnotoad role tests
my $hypnotoad = Mojo::Server::Hypnotoad->with_roles('+Launchd')->new;
is $hypnotoad->prefork->does('Mojo::Server::Prefork::Role::Launchd'), 1,
  'composed correctly';

eval { $hypnotoad->daemonize };
is $@->message, 'Not allowed', 'throws and correct message';

$hypnotoad->{upgrade} = 0;
$hypnotoad->_hot_deploy;
is $hypnotoad->{upgrade}, 0, 'not modified';

$hypnotoad->_manage;
is $hypnotoad->{upgrade}, 0, 'not modified';

isa_ok $hypnotoad->_spawn(200), 'Mojo::Log';

done_testing;

# -*- mode: perl; -*-
use Mojo::Base -strict;
use Test::More;
use Mojo::DOM;
use Mojo::File qw{tempdir};
use Mojo::Home;
use Mojolicious::Command::Author::generate::launchd;
use Capture::Tiny qw{capture_stderr capture_stdout};

my $home = Mojo::Home->new->detect;
$ENV{PATH} = join ':', $home->child('script'), split /:/ => $ENV{PATH};

my $l = new_ok('Mojolicious::Command::Author::generate::launchd');
isa_ok $l, 'Mojolicious::Command';
can_ok $l, qw{description run usage};
$l->app->home($home);

# check the generated classes
$l->_generate_classes;
my ($stderr) = capture_stderr {
    $l->_generate_classes; # no warnings please...
};
is $stderr, '', 'no warnings';

my $env = Mojo::Cmd::gen::launchd::Variable->new(MOJO_MODE => 'development');
is_deeply $env, [MOJO_MODE => 'development'], 'ok';
is $env->name, 'MOJO_MODE', 'name accessor';
is $env->value, 'development', 'value accessor';

like $l->agent_dir, qr{[^~]+/Library/LaunchAgents$}, 'expanded';
like $l->hypnotoad, qr{/hypnotoad-launchd$}, 'found';
is $l->app->moniker, 'mojo-hello_world', 'moniker!';

my $temp = tempdir();
my $label = 'nz.co.awesome.service';

$l->agent_dir("$temp");
$l->run('-inc',
    -mode => 'development',
    -label => $label);
ok -e $l->plist_file, 'output exists';
like $l->plist_file, qr{\Q$label\E.plist$}, 'correct filename';
my $dom = Mojo::DOM->new($l->plist_file->slurp);

my $keys = $dom->find('key');
is $keys->size, 16, 'correct number of keys';
is_deeply $keys->map(sub { $_->text }), [
    qw{Label AbandonProcessGroup RunAtLoad KeepAlive SuccessfulExit Program
    ProgramArguments WorkingDirectory EnvironmentVariables PATH
    HYPNOTOAD_FOREGROUND PERL5LIB MOJO_MODE MOJO_HOME StandardErrorPath
    StandardOutPath}
], 'keys correct';
is $keys->first(sub { $_->text eq 'Label' })->next->text, $label, 'correct label';
# ProgramArguments has <array><string>...</string><string>...</string></array>
my $args = $keys->first(sub { $_->text eq 'ProgramArguments'})->next->children;
is $args->map(sub { $_->text })->grep(qr{^/})->size, 2, 'two options abs paths';

#
# re-run using same instance
#
$l->start_interval(3600);
$l->force(1); # tests will fail otherwise, file not overwritten
$l->run;
$dom = Mojo::DOM->new($l->plist_file->slurp);
$keys = $dom->find('key');
is $keys->size, 16, 'correct number of keys';
is_deeply $keys->map(sub { $_->text }), [
    qw{Label AbandonProcessGroup StartInterval RunAtLoad KeepAlive
    SuccessfulExit Program ProgramArguments WorkingDirectory
    EnvironmentVariables PATH HYPNOTOAD_FOREGROUND MOJO_MODE MOJO_HOME
    StandardErrorPath StandardOutPath}
], 'keys correct';

my $ints = $dom->find('integer');
is_deeply $ints->map(sub { $_->text }), [3600], 'start interval';

my ($launchctl_cmd) = capture_stdout {
    $l->launchd_commands;
};
like $launchctl_cmd, qr/kickstart/, 'includes the kickstart command';

#
# additional environment variables
#
$l->environment([
  'X1=auth1:auth2', 'X2=1', 'X3=http://cpan.metacpan.org/', 'PATH=/save']);
$l->force(1); # tests will fail otherwise, file not overwritten
$l->run;
$dom = Mojo::DOM->new($l->plist_file->slurp);
$keys = $dom->find('key');
is $keys->size, 19, 'correct number of keys';
is_deeply $keys->map(sub { $_->text }), [
    qw{Label AbandonProcessGroup StartInterval RunAtLoad KeepAlive
    SuccessfulExit Program ProgramArguments WorkingDirectory
    EnvironmentVariables PATH HYPNOTOAD_FOREGROUND MOJO_MODE MOJO_HOME X1 X2 X3
    StandardErrorPath StandardOutPath}
], 'keys correct';

done_testing;

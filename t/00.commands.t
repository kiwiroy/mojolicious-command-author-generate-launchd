# -*- mode: perl; -*-
use Mojo::Base -strict;
use Mojo::File 'tempdir';
use Mojo::Home;
use Test::More;
use Capture::Tiny qw{capture capture_stdout};
use Mojolicious::Commands;
use Mojolicious::Command::Author::generate;

if (my $cmd = new_ok 'Mojolicious::Commands') {
    local $ENV{HARNESS_ACTIVE} = 0;
    my ($stdout) = capture_stdout {
        $cmd->run('generate');
    };
    like $stdout, qr/launchd/, 'successfully loaded';
}

if (my $gen = new_ok 'Mojolicious::Command::Author::generate') {
    local $ENV{HARNESS_ACTIVE} = 0;
    my ($stdout) = capture_stdout {
        $gen->run();
    };
    like $stdout, qr/launchd/, 'successfully loaded';
}

if (my $gen = new_ok 'Mojolicious::Command::Author::generate') {
    local $ENV{HARNESS_ACTIVE} = 0;
    local $ENV{PATH} =
      join ':', Mojo::Home->new->detect->child('script'), $ENV{PATH};
    my $output_dir = tempdir;
    my ($stdout, $stderr) = capture {
        $gen->run('launchd', '--output', $output_dir);
    };
    # diag $stdout;
    is -e $output_dir->child('mojo-hello_world.plist'), 1, 'plist written';
}

if (my $gen = new_ok 'Mojolicious::Command::Author::generate') {
    local $ENV{HARNESS_ACTIVE} = 0;
    local $ENV{PATH} =
      join ':', Mojo::Home->new->detect->child('script'), $ENV{PATH};
    my $output_dir = tempdir;
    my ($stdout, $stderr) = capture {
        $gen->run('launchd', '--output', $output_dir, '-chocolate');
    };
    is -e $output_dir->child('mojo-hello_world.plist'), undef, 'plist written';
    like $stdout, qr/launchd/, 'help';
    like $stderr, qr/chocolate/, 'parsing message';
}

done_testing;

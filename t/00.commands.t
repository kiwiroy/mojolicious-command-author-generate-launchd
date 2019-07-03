# -*- mode: perl; -*-
use Mojo::Base -strict;
use Test::More;
use Capture::Tiny qw{capture_stdout};
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

done_testing;

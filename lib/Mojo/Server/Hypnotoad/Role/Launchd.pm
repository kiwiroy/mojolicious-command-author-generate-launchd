package Mojo::Server::Hypnotoad::Role::Launchd;

use Mojo::Base qw{-role -signatures};
use Mojo::Exception;
use Mojo::Server::Prefork;
use File::Which qw{which};
use Mojo::Util qw{steady_time};

after configure => sub ($self, @args) {
    ## extra protection for plugin Config => {}
    $self->prefork
        ->listen($self->prefork->app->config->{hypnotoad}{listen} = [])
        ->max_clients($self->prefork->app->config->{hypnotoad}{clients} = 0);
};

# specialise the Prefork
has prefork => sub {
    my $self = shift;
    Mojo::Server::Prefork->with_roles('+Launchd')->new()
        ->tap(sub {
            $_->on(spawn => sub ($e, $pid) { $self->_spawn($pid) });
        });
};

around run => sub ($orig, $self, @args) {
    # manage environment variables for specific case.
    $ENV{HYPNOTOAD_EXE} = which 'hypnotoad';
    # no daemonize or clean start!
    $ENV{HYPNOTOAD_FOREGROUND} = $ENV{HYPNOTOAD_REV} = 1;
    $ENV{MOJO_MORBO_TIMEOUT}   = 1;
    # chain
    $self->$orig(@args);
    $self->prefork->app->log->info("This is the end.", '-' x 80);
};

sub daemonize {
    Mojo::Exception->throw("Not allowed");
}

sub _hot_deploy ($self) {
    # Make sure server is running
    return unless my $pid = shift->prefork->check_pid;
    # flag for upgrade, leave a message, but don't exit
    $self->{upgrade} ||= steady_time;
    $self->prefork
        ->app->log->debug("Prepared hot deployment for Hypnotoad server $pid.");
}

sub _manage ($self) {
    my $prefork = $self->prefork;
    my $log     = $prefork->app->log;
    if ($self->{upgrade} && !$self->{finished}) {
        my $pid = $prefork->check_pid;
        $log->info("Starting zero downtime software upgrade for $pid");
        $prefork->check_pid if ($pid && kill USR2 => $pid);
        delete $self->{upgrade};
    }
}

sub _spawn ($self, $pid) {
    $self->prefork->app->log->info("hypnotoad pid=$pid");
}

1;

=encoding utf8

=head1 NAME

Mojo::Server::Hypnotoad::Role::Launchd - Specialised for launchd

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut

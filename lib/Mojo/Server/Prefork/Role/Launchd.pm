package Mojo::Server::Prefork::Role::Launchd;

use Mojo::Base qw{-role -signatures};
use Mojo::Exception;
use Mojo::File qw{path};
use Mojo::Loader 'load_class';
use Mojo::Util 'steady_time';
use POSIX 'WNOHANG';

has auto_restart => 0;
has backend => sub {
  my $backend = $ENV{MOJO_MORBO_BACKEND} || 'Poll';
  $backend = "Mojo::Server::Morbo::Backend::$backend";
  return $backend->with_roles('+CacheUpdate')->new(watch => [])
    unless my $e = load_class $backend;
  die $e if ref $e;
  die qq{Can't find Morbo backend class "$backend" in \@INC. (@INC)\n};
};

after load_app => sub ($self, @args) {
    _modify_log($self)
        ->max_clients(0)
        ->listen([])
        ->app->log->debug("prefork load_app()");
};

sub run ($self) {
    $self->app->log->info("launchd controller $$ started");
    $self->check_pid;
    local $SIG{CHLD} = sub {
        # $self->app->log->warn("CHLD received!");
        while ((my $pid = waitpid -1, WNOHANG) > 0) {
            $self->emit(reap => $pid)->_stopped($pid);
        }
    };
    local $SIG{INT} = local $SIG{QUIT} = local $SIG{TERM} = sub {
        my $pid = $self->check_pid;
        $self->check_pid if ($pid && kill TERM => $pid);
        $self->_term(1);
        $self->{finished} = !($self->{running} = 0);
    };
    local $SIG{TTIN} = sub {
        my $pid = $self->check_pid;
        $self->check_pid if ($pid && kill TTIN => $pid);
    };
    local $SIG{TTOU} = sub {
        my $pid = $self->check_pid;
        $self->check_pid if ($pid && kill TTOU => $pid);
    };
    $self->{running} = 1;
    $self->_manage while $self->{running};

    $self->app->log->info("launchd controller $$ stopped");
}

#
# internal
#
sub _add_watch ($self, @watch) {
    my $log = $self->app->log;
    my $watching = $self->backend->watch;
    for my $w(@watch) {
        unshift @$watching, $w unless grep { $_ eq $w } @$watching;
    }
    $self;
}

sub _catch_modified ($self, $file) {
    my ($pid) = split /\n/, path($file)->slurp;
    $self->{hypnotoad} = $pid;
    $self->{pool}{$pid}{time}    = steady_time;
    $self->{pool}{$pid}{waiting} = 0;
    $self->app->log->info("hypnotoad ($pid) started");
}

sub _catch_unlink ($self, $file) {
    my $pid = $self->{hypnotoad};
    $self->app->log->info("hypnotoad (" . ($pid || ''). ") died");
    $self->{finished} = !($self->{running} = 0) unless $self->auto_restart;
    delete $self->{hypnotoad};
}

sub _hypnotoad_start_or_capture ($self) {
    # is the daemon already running an has a pid file?
    my $running = $self->check_pid;
    return $running if $running;
    # have we already tried - missing a pid file?
    # return 1 if grep { $_->{waiting} } values %{$self->{pool}};
    {
        local $ENV{HYPNOTOAD_FOREGROUND} = 0; # daemonize
        local $ENV{HYPNOTOAD_REV}        = 0; # clean start
        die "Can't fork: $!" unless defined(my $pid = $running = fork);
        exec $^X, $ENV{HYPNOTOAD_EXE} or die "Can't exec: $!" unless $pid;
        $self->emit(spawn => $pid)->{pool}{$pid} = {
            time    => steady_time,
            waiting => 1
        };
    }
    return $running;
}

sub _listen {
    Mojo::Exception->throw("Prefork Launchd must not listen");
}

sub _manage ($self){
    $self->app->log->debug("prefork _manage() ". ($self->{hypnotoad} || '*0*'));
    if (!$self->{hypnotoad} && !$self->{finished}) {
        $self->_add_watch($self->app->config->{hypnotoad}{pid_file});
        $self->{hypnotoad} = $self->_hypnotoad_start_or_capture;
    }

    if (my @files = @{$self->backend->modified_files}) {
        # default to role style
        @files = map { ref($_) eq 'ARRAY' ? $_ : [$_, 'MODIFIED'] } @files;
        $self->app->log->debug(qq{@{[scalar @files]} files changed, ...});
        for my $file(@files) {
            my ($path, $event) = @$file;
            $self->app->log->info(qq{$path was $event.});
            _catch_modified($self, $path) if $event eq 'MODIFIED';
            _catch_unlink($self, $path) if $event eq 'UNLINKED';
        }
    }
    $self->emit('wait');
}

sub _modify_log ($self) {
    my $log = $self->app->log;
    $log->path(path($log->path)->sibling('launchd.log')) if $log->path;
    $self;
}

sub _stopped {
  my ($self, $pid) = @_;

  return unless my $w = delete $self->{pool}{$pid};

  my $log = $self->app->log;
  $log->debug("hypnotoad $pid stopped()/daemonize()");
  # hypnotoad_start_or_capture() will update with check_pid
  delete $self->{hypnotoad} if $pid == $self->{hypnotoad};
}

1;

=encoding utf8

=head1 NAME

Mojo::Server::Prefork::Role::Launchd - Specialised for launchd

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut

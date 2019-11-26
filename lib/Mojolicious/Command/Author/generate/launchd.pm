package Mojolicious::Command::Author::generate::launchd;

use Mojo::Base qw{Mojolicious::Commands -signatures};
use Mojo::Collection 'c';
use Mojo::Exception;
use Mojo::File;
use Mojo::Loader qw{data_section};
use Mojo::Util 'getopt';
use File::Glob ':glob';
use File::Which qw{which};

our $VERSION = 0.2;

has agent_dir      => \&_default_launch_agent_dir;
has description    => 'Create a launchd.plist file for application';
has environment    => sub { [] };
has extension      => 'plist';
has force          => 0;
has start_interval => 0;
has hypnotoad      => sub { which 'hypnotoad-launchd'; };
has plist_file     => sub ($self) {
  return Mojo::File->new($self->agent_dir)
    ->child(join '.', $self->app->moniker, $self->extension);
};
has usage => sub { shift->extract_usage };

sub launchd_commands ($self) {
  return $self if $self->quiet;
  $self->_loud('');
  $self->_loud($self->render_data('launchctl.cmds', {self => $self}));
  return $self;
}

sub run ($self, @args) {
  Mojo::Exception->throw('unable to locate hypnotoad') unless $self->hypnotoad;
  $self->environment;
  my $status = getopt \@args,
    'environ=s@' => \$self->{environment},
    'force'      => \$self->{force},
    'home=s'     => \my $home,
    'inc'        => \my $inc,
    'interval=i' => \$self->{start_interval},
    'label=s'    => \my $label,
    'mode=s'     => \my $mode,
    'output=s'   => \my $agent_dir,
    'quiet'      => \$self->{quiet},
    ;
  return $self->help unless $status;
  $mode ||= $ENV{MOJO_MODE} ||= $self->app->mode;
  $home ||= $ENV{MOJO_HOME} ||= $self->app->home;
  $home = (ref($home) ? $home : Mojo::File->new($home))->to_abs;
  $self->app->moniker($label)  if $label;
  $self->agent_dir($agent_dir) if $agent_dir;
  $self->_generate_classes;
  my $env = c();
  push @$env, Mojo::Cmd::gen::launchd::Variable->new(path => $self->_path),
    Mojo::Cmd::gen::launchd::Variable->new(hypnotoad_foreground => 1);
  push @$env, Mojo::Cmd::gen::launchd::Variable->new(perl5lib => $ENV{PERL5LIB})
    if $inc;
  push @$env, Mojo::Cmd::gen::launchd::Variable->new(mojo_mode => $mode);
  push @$env, Mojo::Cmd::gen::launchd::Variable->new(mojo_home => $home);
  push @$env, Mojo::Cmd::gen::launchd::Variable->new(split /=/, $_, 2)
    for @{$self->environment};

  my $log = $self->app->log;
  $log->path($self->app->home->child('log/' . $self->app->moniker))
    unless $log->path;
  $self->_loud('  [env] '
      . $env->map(sub { join '=' => $_->name, $_->value })
      ->sort->join("\n        "));
  $self->_loud('  [unlink] ' . $self->plist_file)->plist_file->remove
    if $self->force;
  $self->render_to_file(
    'hypnotoad.plist',
    $self->plist_file,
    {
      app                => $self->app,
      hypnotoad          => $self->hypnotoad,
      application_script => Mojo::File->new($0)->to_abs->to_string,
      environment        => $env->uniq(sub { lc $_->name }),
      abandonprocessgroup => 'false',                  # true of false
      start_interval      => $self->start_interval,    # e.g. 3600
    }
  );
  return $self->launchd_commands;
}

sub _default_launch_agent_dir {
  my $flags = GLOB_NOCHECK | GLOB_QUOTE | GLOB_TILDE | GLOB_ERR;
  return Mojo::File->new(bsd_glob '~/Library/LaunchAgents', $flags)->to_string;
}

sub _generate_classes ($self) {
  state $x = 0;
  return $self if ($x++ > 0);
  eval data_section __PACKAGE__, 'EnvironmentVariable.pm';
  Mojo::Exception->throw($@) if $@;
  return $self;
}

sub _hypnotoad_path_entry ($self) {
  my $toad = $self->hypnotoad;
  if (!$toad) {
    $self->log->fatal('Cannot find hypnotoad');
    Mojo::Exception->throw('Cannot find hypnotoad');
  }
  return Mojo::File->new($toad)->dirname;
}

sub _minimal_path ($self) {
  return c(split ':', $ENV{PATH})->grep(qr{^/(opt|usr|bin|sbin)\b});
}

sub _path ($self) {
  my $p = $self->_minimal_path;
  unshift @$p, $self->_perl_path_entry;
  unshift @$p, $self->_hypnotoad_path_entry;
  return $p->uniq->join(':');
}

sub _perl_path_entry ($self) {
  Mojo::File->new($^X)->dirname;
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Command::Author::generate::launchd - Create a launchd.plist file for application

=head1 SYNOPSIS

Usage:

  APPLICATION generate launchd [--inc] [-force] [--mode <mode>] [--label <label>] [--output <dir>] [--interval <seconds>] ...

Options:
  --environ        Additional app specific environment variables
                   e.g. name=value
  --inc            Include the current PERL5LIB in Environment     [off]
  --force          Flag to force overwriting of existing plist file
  --mode <mode>    Set the MOJO_MODE.                              [production]
  --home <path>    Set the MOJO_HOME.
  --label <label>  Set the label and thus filename of the agent    [app->moniker]
  --output <dir>   Alter the output directory for the plist file   [~/Library/LaunchAgents]
  --interval <sec> Experimental: set restart period

  --quiet          Silence the messages.
  --help           Show this usage information.

=head1 DESCRIPTION

Create a launchd.plist file for application, based on the included template file.

=head1 METHODS

=head2 launchd_commands

=head2 run

=head1 KNOWN NUISANCE

=head2 hypnotoad

Zero downtime upgrades are not possible. This is an architectural challenge with
launchd. It is designed to manage all processes of an agent/daemon rather than
have a master process manage the forked children itself. For this reason,
hypnotoad is run in foreground mode. The fork/exec used in the zero downtime
results in launchd receiving a CHLD signal and sending a TERM to the process
group with AbandonProcessGroup=false, or losing track of the process in the case
of AbandonProcessGroup=true - the fork/exec does not replace the image in the
original process, but creates a child. What does happen is a minimal downtime
upgrade, where a USR2 signal is received, an upgrade is attempted, if successful
the launchctl tracked process is gracefully shutdown, the process groups sent a
TERM signal and with KeepAlive.SuccessfulExit=true a new agent started by
launchd.

=head2 hypnotoad-launchd

This script, similar to C<hypnotoad>, is a solution to the issue above.

=head1 SEE ALSO

=over 4

=item L<http://launchd.info/>

=item L<https://www.soma-zone.com/LaunchControl/>

=item L<https://github.com/tjluoma/launchd-keepalive>

=item L<http://launched.zerowidth.com>

=item L<https://nathangrigg.com/2012/07/schedule-jobs-using-launchd>

=item Man pages

C<man launchd> and C<man launchd.plist> contain useful reference. There is also
archived documentation from L<Apple|https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html>

=back

=head1 CONTRIBUTORS

=over 4

=item Roy Storey (kiwiroy)

=back

=cut

__DATA__
@@ EnvironmentVariable.pm
package
    Mojo::Cmd::gen::launchd::Variable;
use Mojo::Base qw{Mojo::Collection -signatures};
sub name ($self) { $self->[0] }
sub value ($self) { $self->[1] }
1;
@@ launchctl.cmds

This generator did not deploy the plist. Use these launchctl commands:

% if ($self->force) {
  # unload the agent
  launchctl unload <%= $self->plist_file %>
% }
  # load the agent
  launchctl load -w <%= $self->plist_file %>
  # list the agent
  launchctl list <%= $self->app->moniker %>
  # print information on the agent
  launchctl print gui/$(id -u)/<%= $self->app->moniker %>
  # start
  launchctl start <%= $self->app->moniker %>
  # stop
  launchctl stop <%= $self->app->moniker %>
  # add workers
  launchctl kill TTIN gui/$(id -u)/<%= $self->app->moniker %>
  # attempt zero downtime... unfortunately
  launchctl kill USR2 gui/$(id -u)/<%= $self->app->moniker %>
  # kickstart and report pid
  launchctl kickstart -p gui/$(id -u)/<%= $self->app->moniker %>

@@ hypnotoad.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
 <dict>

   <key>Label</key>
   <string><%= $app->moniker; %></string>

   <key>AbandonProcessGroup</key>
   <<%= $abandonprocessgroup %>/>

 % if ($start_interval) {
   <key>StartInterval</key>
   <integer><%= $start_interval %></integer>
 % }
   <key>RunAtLoad</key>
   <true/>

   <key>KeepAlive</key>
   <dict>
       <key>SuccessfulExit</key>
       <true/>
   </dict>

   <key>Program</key>
   <string><%= $hypnotoad %></string>
   <key>ProgramArguments</key>
   <array>
       <string><%= $hypnotoad %></string>
       <string><%= $application_script %></string>
   </array>

   <key>WorkingDirectory</key>
   <string><%= $app->home %></string>

   <key>EnvironmentVariables</key>
   <dict>
   % for my $var($environment->each) {
          <key><%= uc $var->name %></key>
          <string><%= $var->value %></string>
   % }
   </dict>

   <key>StandardErrorPath</key>
   <string><%= $app->log->path %>.1.log</string>

   <key>StandardOutPath</key>
   <string><%= $app->log->path %>.1.log</string>

 </dict>
</plist>

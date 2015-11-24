use strict;
use warnings;
use 5.020;
use Database::Server;

package Database::Server::MySQL {

  # ABSTRACT: Interface for MySQL server instance

=head1 SYNOPSIS

 use Database::Server::MySQL;
 my $server = Database::Server::MySQL->new(
   data     => '/tmp/mysqlroot/data',
   pid_file => '/tmp/mysqlroot/mysql.pid',
 );
 
 $server->create;
 $server->start;
 $server->stop;
 
 if($server->is_up)
 {
   say "server is up";
 }
 else
 {
   say "server is down";
 }

=head1 DESCRIPTION

This class provides a simple interface for creating,
starting and stopping MySQL instances.  It should also
work with MariaDB and other compatible forks.

=cut

  use Moose;
  use MooseX::Types::Path::Class qw( File Dir );
  use File::Which qw( which );
  use Carp qw( croak );
  use namespace::autoclean;

  with 'Database::Server::Role::Server';

  # TODO: my version of Debian comes with a MySQL old
  # enough that you have to use this deprecated
  # interface for creating MySQL data files.  This
  # has to be able to handle which() returning new
  # or L</create> below needs to check the server
  # version.  First though we need a working modern
  # version of MySQL to test against.
  has mysql_install_db => (
    is      => 'ro',
    isa     => File,
    lazy    => 1,
    coerce  => 1,
    default => sub {
      scalar which('mysql_install_db');
    },
  );

  # we can probably use mysqld_safe instaed?
  # on Debian at least mysqld is in /usr/sbin
  # and thus not normally in the path.
  has mysqld => (
    is      => 'ro',
    isa     => File,
    lazy    => 1,
    coerce  => 1,
    default => sub {
      scalar which('mysqld');
    },
  );

  has mysqld_safe => (
    is      => 'ro',
    isa     => File,
    lazy    => 1,
    coerce  => 1,
    default => sub {
      scalar which('mysqld_safe') // croak "unable to find mysqld_safe";
    },
  );

=head1 ATTRIBUTES

=head2 data

 my $dir = $server->data;

The data directory root for the server.  This
attribute is required.

=cut
  
  has data => (
    is       => 'ro',
    isa      => Dir,
    coerce   => 1,
    required => 1,
  );

=head2 pid_file

 my $file = $server->pid_file

The PID file for the server.  This attribute
is required.

=cut

  has pid_file => (
    is       => 'ro',
    isa      => File,
    coerce   => 1,
    required => 1,
  );

=head2 user

 my $user = $server->user;

The user the server will run under.  The default is
the user that is running the Perl process.

=cut

  has user => (
    is      => 'ro',
    isa     => 'Str',
    lazy    => 1,
    default => sub {
      scalar getpwuid($<);
    },
  );

=head2 port

 my $port = $server->port;

The TCP port to listen to connections on.

=cut

  has port => (
    is  => 'ro',
    isa => 'Int',
  );

=head2 socket

 my $sock = $server->socket;

The path to the UNIX domain socket.

=cut

  has socket => (
    is => 'ro',
    isa => File,
  );

=head2 log_error

 my $log = $server->log_error;

The error log file path.  If not provided then
errors will be sent to syslog.

=cut

  has log_error => (
    is       => 'ro',
    isa      => File,
    coerce   => 1,
  );
  
=head1 METHODS

=head2 create

 $server->create;

Create the MySQL instance.  This involves calling C<mysqld --initalize> or
C<mysql_install_db> with the appropriate options to produce the data files
necessary for running the MySQL server instance.

=cut
  
  sub create
  {
    my($self) = @_;
    croak "@{[ $self->data ]} is not empty" if $self->data->children;
    if($self->mysql_install_db)
    {
      return $self->run($self->mysql_install_db, '--datadir=' . $self->data, '--user=' . $self->user);
    }
    elsif($self->mysqld)
    {
      warn "using untested mysqld --initialize";
      # NOTE: if yousee this warning:
      # I am unable to test this as all of the Debian and RedHat based systems that
      # have available to test against have MySQL prior to 5.7.6.  If you are running
      # on such a system please drop me a line so that we can colaborate and make
      # this work (or at least remove the warning if it DOES work).
      return $self->run($self->mysqld, '--initialize', '--user=' . $self->user, '--datadir=' . $self->data );
    }
    else
    {
      croak "unable to find either mysqld_install_db or mysqld"
    }
  }
  
  sub _result
  {
    shift;
    Database::Server::MySQL::InternalResult->new(@_);
  }

=head2 start

 $server->start;

Starts the MySQL database instance.

=cut
  
  sub start
  {
    my($self) = @_;
    
    return $self->_result('server is already running') if $self->is_up;

    my $pid = fork;
    
    if($pid == 0)
    {
      # TODO: maybe capture this in a place the parent can see it
      open STDOUT, '>', '/dev/null';
      open STDERR, '>', '/dev/null';
      exec($self->mysqld_safe,
                             '--datadir='   . $self->data,
                             '--pid-file='  . $self->pid_file,
        $self->log_error ? ( '--log_error=' . $self->log_error )    : ('--syslog'),
        $self->port    ?   ( '--port='      . $self->port )         : (),
        $self->socket  ?   ( '--socket='    . $self->socket )       : (),
      );
      exit 2;
    }
    
    while(1..30)
    {
      last if $self->is_up;
      sleep 1;
    }
    
    $self->is_up ? $self->_result('' => 1) : $self->('server did not start');
  }
  
=head2 stop

 $server->stop;

Stops the MySQL database instance.

=cut

  sub stop
  {
    my($self) = @_;

    return $self->_result('server is not running') unless $self->is_up;
    
    my $pid = $self->pid_file->slurp;
    chomp $pid;
    kill 'TERM', $pid;
    
    while(1..30)
    {
      last unless $self->is_up;
      sleep 1;
    }

    !$self->is_up ? $self->_result('' => 1) : $self->('server did not stop');
    
  }

=head2 is_up

 my $bool = $server->is_up;

Checks to see if the MySQL database instance is up.

=cut

  sub is_up
  {
    my($self) = @_;
    return '' unless -r $self->pid_file;
    my($pid) = $self->pid_file->slurp;
    chomp $pid;
    !!-e "/proc/$pid";
  }
  
}

package Database::Server::MySQL::InternalResult {

  use Moose;
  use namespace::autoclean;

  with 'Database::Server::Role::Result';
  
  has message => (
    is  => 'ro',
    isa => 'Str',
  );
  
  has ok => (
    is  => 'ro',
    isa => 'Int',
  );

  sub BUILDARGS
  {
    my($class, $message, $ok) = @_;
    { ok => $ok // '', message => $message };
  }
  
  sub is_success
  {
    shift->ok;
  }  

}

1;

use strict;
use warnings;
use 5.020;

package Database::Server::MySQL {

  # ABSTRACT: Interface for MySQL server instance
  # VERSION

  use Moose;
  use MooseX::Types::Path::Class qw( File Dir );
  use File::Which qw( which );
  use Carp qw( croak );
  use namespace::autoclean;

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
  
  has user => (
    is      => 'ro',
    isa     => 'Str',
    lazy    => 1,
    default => sub {
      scalar getpwuid($<);
    },
  );

  has data => (
    is       => 'ro',
    isa      => Dir,
    coerce   => 1,
    required => 1,
  );

  has pid_file => (
    is       => 'ro',
    isa      => File,
    coerce   => 1,
    required => 1,
  );

  has port => (
    is  => 'ro',
    isa => 'Int',
  );
  
  has socket => (
    is => 'ro',
    isa => File,
  );
  
  has log_error => (
    is       => 'ro',
    isa      => File,
    coerce   => 1,
    required => 1,
  );
  
  has syslog  => (
    is      => 'ro',
    default => 0,
  );
  
  sub _run
  {
    my($self, @command) = @_;
    Database::Server::MySQL::CommandResult->new(@command);
  }
  
  sub create
  {
    my($self) = @_;
    croak "@{[ $self->data ]} is not empty" if $self->data->children;
    if($self->mysql_install_db)
    {
      return $self->_run($self->mysql_install_db, '--datadir=' . $self->data, '--user=' . $self->user);
    }
    elsif($self->mysqld)
    {
      return $self->_run($self->mysqld, '--initialize', '--user=' . $self->user);
    }
    else
    {
      croak "unable to find either mysqld_install_db or mysqld"
    }
  }
  
  sub is_up
  {
    my($self) = @_;
    return '' unless -r $self->pid_file;
    my($pid) = $self->pid_file->slurp;
    chomp $pid;
    # FIXME: only works with /proc fs
    !!-e "/proc/$pid";
  }
  
  sub _result
  {
    shift;
    Database::Server::MySQL::InternalResult->new(@_);
  }
  
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
                          '--log_error=' . $self->log_error,
        !$self->syslog ? ('--skip-syslog')                       : (),
        $self->port    ? ('--port='      . $self->port)          : (),
        $self->socket  ? ('--socket='    . $self->socket)        : (),
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

}

package Database::Server::MySQL::Result {

  use Moose::Role;
  use namespace::autoclean;

  requires 'is_success';
  
}

package Database::Server::MySQL::InternalResult {

  use Moose;
  use namespace::autoclean;

  with 'Database::Server::MySQL::Result';
  
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

package Database::Server::MySQL::CommandResult {

  use Moose;
  use Capture::Tiny qw( capture );
  use Carp qw( croak );
  use experimental qw( postderef );
  use namespace::autoclean;

  with 'Database::Server::MySQL::Result';

  sub BUILDARGS
  {
    my $class = shift;
    my %args = ( command => [map { "$_" } @_] );
    
    ($args{out}, $args{err}) = capture { system $args{command}->@* };
    croak "failed to execute @{[ $args{command}->@* ]}: $?" if $? == -1;
    my $signal = $? & 127;
    croak "command @{[ $args{command}->@* ]} killed by signal $signal" if $args{signal};

    $args{exit}   = $args{signal} ? 0 : $? >> 8;
        
    \%args;
  }

  has command => (
    is  => 'ro',
    isa => 'ArrayRef[Str]',
  );

  has out => (
    is  => 'ro',
    isa => 'Str',
  );

  has err => (
    is  => 'ro',
    isa => 'Str',
  );
  
  has exit => (
    is  => 'ro',
    isa => 'Int',
  );
  
  sub is_success
  {
    !shift->exit;
  }
  
  __PACKAGE__->meta->make_immutable;
}

1;

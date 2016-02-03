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
 
 $server->init;
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
  use Path::Class qw( file dir );
  use File::Which qw( which );
  use Carp qw( croak );
  use File::Temp qw( tempfile );
  use File::Temp qw( tempdir );
  use JSON::PP ();
  use PerlX::Maybe qw( maybe provided );
  use namespace::autoclean;

  with 'Database::Server::Role::Server';

  # TODO: my version of Debian comes with a MySQL old
  # enough that you have to use this deprecated
  # interface for creating MySQL data files.  This
  # has to be able to handle which() returning new
  # or L</init> below needs to check the server
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

  has mysql => (
    is      => 'ro',
    isa     => File,
    lazy    => 1,
    coerce  => 1,
    default => sub {
      scalar which('mysql');
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
    is     => 'ro',
    coerce => 1,
    isa    => File,
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

=head2 skip_grant_tables

 my $bool = $server->skip_grant_tables;

Start without grant tables.  This gives all users FULL
ACCESS to all tables.

=cut

  has skip_grant_tables => (
    is      => 'ro',
    isa     => 'Int',
    default => 0,
  );

=head2 skip_networking

 my $bool = $server->skip_networking;

Don't allow connection with TCP/IP.

=cut

  has skip_networking => (
    is      => 'ro',
    isa     => 'Int',
    default => 0,
  );

=head2 mylogin_cnf

 my $file = $server->mylogin_cnf;

Location of the C<.mylogin.conf> file which contains the login details for
connecting to the server.  This file will be generated when the any of
the L</init>, L</start> or L</restart> methods are called.

=cut

  has mylogin_cnf => (
    is     => 'ro',
    isa    => File,
    coerce => 1,
  );

=head1 METHODS

=head2 init

 $server->init;

Create the MySQL instance.  This involves calling C<mysqld --initalize> or
C<mysql_install_db> with the appropriate options to produce the data files
necessary for running the MySQL server instance.

=cut
  
  sub init
  {
    my($self) = @_;
    croak "@{[ $self->data ]} is not empty" if $self->data->children;
    
    $self->_update_mylogin_cnf;
    
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
  
  sub _update_mylogin_cnf
  {
    my($self) = @_;
    return unless $self->mylogin_cnf;
    
    require Config::INI::Writer;
    
    Config::INI::Writer->write_file([
      '_' => [],
      client => {
        maybe port   => $self->port,
        maybe socket => $self->socket,
        provided !$self->skip_networking, host => '127.0.0.1',
      },
    ], $self->mylogin_cnf);
  }
  
=head2 create

 my $args = Database::Server::MySQL->create($root);

(class method)
Create, initialize a MySQL instance, rooted under C<$root>.  Returns
a hash reference which can be passed into C<new> to reconstitute the
database instance.  Example:

 my $arg = Database::Server::MySQL->create("/tmp/foo");
 my $server = Database::Server::MySQL->new(%$arg);

=cut

  sub create
  {
    my(undef, $root) = @_;
    $root = Dir->coerce($root);
    my $data = $root->subdir( qw( var lib data mysql ) );
    my $run  = $root->subdir( qw( var run ) );
    my $log  = $root->file( qw( var log mysql.log) );
    my $etc  = $root->subdir( qw( etc ) );
    $_->mkpath(0, 0700) for ($data,$run,$etc,$log->parent);
    
    my %arg = (
      data              => $data->stringify,
      pid_file          => $run->file('mysql.pid')->stringify,
      #port             => Database::Server->generate_port,
      socket            => $run->file('mysql.sock')->stringify,
      log_error         => $log->stringify,
      skip_grant_tables => 1,
      skip_networking   => 1,
      mylogin_cnf       => $etc->file('mylogin.cnf')->stringify,
    );

    # TODO: check return value    
    __PACKAGE__->new(%arg)->init;
    
    \%arg;
  }

=head2 start

 $server->start;

Starts the MySQL database instance.

=cut
  
  sub start
  {
    my($self) = @_;
    
    $self->_update_mylogin_cnf;

    return $self->fail('server is already running') if $self->is_up;

    $self->runnb($self->mysqld_safe,
                           '--no-defaults',
                           '--datadir='   . $self->data,
                           '--pid-file='  . $self->pid_file,
      $self->log_error ? ( '--log_error=' . $self->log_error )    : ('--syslog'),
      $self->port    ?   ( '--port='      . $self->port )         : (),
      $self->socket  ?   ( '--socket='    . $self->socket )       : (),
        
      $self->skip_grant_tables ? ( '--skip-grant-tables' ) : (),
      $self->skip_networking ?   ( '--skip-networking'   ) : (),
    );
  }
  
=head2 stop

 $server->stop;

Stops the MySQL database instance.

=cut

  sub stop
  {
    my($self) = @_;

    return $self->fail('server is not running') unless $self->is_up;
    
    my $pid = $self->pid_file->slurp;
    chomp $pid;
    kill 'TERM', $pid;
    
    for(1..30)
    {
      last unless $self->is_up;
      sleep 1;
    }

    !$self->is_up ? $self->good : $self->fail('server did not stop');
    
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

  sub _shell_args
  {
    my($self) = @_;
    ('--no-defaults', $self->socket ? ('--socket' => $self->socket) : ('--port' => $self->port, '--host' => '127.0.0.1'));
  }

=head2 list_databases

 my @names = $server->list_databases;
 
Returns a list of the databases on the MySQL instance.

=cut

  sub list_databases
  {
    my($self) = @_;
    my $ret = $self->run($self->mysql, $self->_shell_args, '-B', -e => 'show databases');
    my @list = split /\n/, $ret->out;
    shift @list;
    @list;
  }

=head2 create_database

 $server->create_database($dbname);

Create a new database with the given name.

=cut

  sub create_database
  {
    my($self, $dbname) = @_;
    croak "no database name provided" unless $dbname;
    $self->run($self->mysql, $self->_shell_args, -e => "CREATE DATABASE $dbname");
    $self;
  }
  
=head2 drop_database

 $server->drop_database($dbname);

Drop database with the given name.

=cut

  sub drop_database
  {
    my($self, $dbname) = @_;
    croak "no database name provided" unless $dbname;
    $self->run($self->mysql, $self->_shell_args, -e => "DROP DATABASE $dbname");
    $self;
  }
  
=head2 interactive_shell

 $server->interactive_shell($dbname);
 $server->interactive_shell;

Connect to the database using an interactive shell.

=cut

  sub interactive_shell
  {
    my($self, $dbname, %args) = @_;
    my @args = $self->mysql, $self->_shell_args, $dbname ? ($dbname) : ();
    $args{exec} ? exec @args : $self->run(@args);
    $self;
  }

=head2 shell

 $server->shell($dbname, $sql, \@options);

Connect to the database using a non-interactive shell.

=over 4

=item C<$dbname>

The name of the database

=item C<$sql>

The SQL to execute.

=item C<\@options>

The C<mysql> options to use.

=back

=cut
  
  sub shell
  {
    my($self, $dbname, $sql, $options) = @_;
    $options //= [];
    my($fh, $filename) = tempfile("mysqlXXXX", SUFFIX => '.sql');
    print $fh $sql;
    close $fh;
    open STDIN, '<', $filename;
    my $ret = $self->run($self->mysql, $self->_shell_args, @$options, $dbname ? ($dbname) : ());
    open STDIN, '<', '/dev/null';
    unlink $filename;
    $ret;
  }

=head2 dsn

 my $dsn = $server->dsn($driver, $dbname);
 my $dsn = $server->dsn($driver);
 my $dsn = $server->dsn;

Provide a DSN that can be fed into DBI to connect to the database using L<DBI>.  These drivers are supported: L<DBD::Pg>, L<DBD::PgPP>, L<DBD::PgPPSjis>.

=cut

  sub dsn
  {
    my($self, $driver, $dbname) = @_;
    $dbname //= 'mysql';
    $driver //= 'mysql';
    $driver =~ s/^DBD:://;
    # DBD::mysql doesn't support mysq_socket.
    croak "Do not know how to generate DNS for DBD::$driver" unless $driver eq 'mysql';
    $self->socket
      ? "DBI:mysql:database=$dbname;mysql_socket=@{[ $self->socket ]}"
      : "DBI:mysql:database=$dbname;host=127.0.0.1;port=@{[ $self->port ]}";
  }
  

#create_database', 'drop_database', 'dsn', 'interactive_shell', 'list_databases', and 'shell'

#=head2 env
#
# my %env = $server->env;
#
#Returns a hash of the environment variables needed to connect to the
#MySQL instance with the native tools (for example C<psql>).  Usually
#this includes the correct value for C<MYSQL_TEST_LOGIN_FILE>, which
#corresponds to the C<.mylogin.cnf> file generated when the database
#was started.  This method requires that the L</mylogin_cnf> attribute
#has been provided when the server object was created.
#
#=cut
#
#  sub env
#  {
#    my($self) = @_;
#    
#    croak "\$server->env for Database::Server::MySQL requires mylogin_cnf"
#      unless  $self->mylogin_cnf;
#    
#    my %env = (
#      MYSQL_TEST_LOGIN_FILE => $self->mylogin_cnf->stringify,
#    );
#
#    %env;
#  }

  before 'restart' => sub { shift->_update_mylogin_cnf };

}

1;

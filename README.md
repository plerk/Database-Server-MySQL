# Database::Server::MySQL [![Build Status](https://secure.travis-ci.org/plicease/Database-Server-MySQL.png)](http://travis-ci.org/plicease/Database-Server-MySQL)

Interface for MySQL server instance

# SYNOPSIS

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

# DESCRIPTION

This class provides a simple interface for creating,
starting and stopping MySQL instances.  It should also
work with MariaDB and other compatible forks.

# ATTRIBUTES

## data

    my $dir = $server->data;

The data directory root for the server.  This
attribute is required.

## pid\_file

    my $file = $server->pid_file

The PID file for the server.  This attribute
is required.

## user

    my $user = $server->user;

The user the server will run under.  The default is
the user that is running the Perl process.

## port

    my $port = $server->port;

The TCP port to listen to connections on.

## socket

    my $sock = $server->socket;

The path to the UNIX domain socket.

## log\_error

    my $log = $server->log_error;

The error log file path.  If not provided then
errors will be sent to syslog.

## skip\_grant\_tables

    my $bool = $server->skip_grant_tables;

Start without grant tables.  This gives all users FULL
ACCESS to all tables.

## skip\_networking

    my $bool = $server->skip_networking;

Don't allow connection with TCP/IP.

## mylogin\_cnf

    my $file = $server->mylogin_cnf;

Location of the `.mylogin.conf` file which contains the login details for
connecting to the server.  This file will be generated when the any of
the ["init"](#init), ["start"](#start) or ["restart"](#restart) methods are called.

# METHODS

## init

    $server->init;

Create the MySQL instance.  This involves calling `mysqld --initalize` or
`mysql_install_db` with the appropriate options to produce the data files
necessary for running the MySQL server instance.

## create

    my $args = Database::Server::MySQL->create($root);

(class method)
Create, initialize a MySQL instance, rooted under `$root`.  Returns
a hash reference which can be passed into `new` to reconstitute the
database instance.  Example:

    my $arg = Database::Server::MySQL->create("/tmp/foo");
    my $server = Database::Server::MySQL->new(%$arg);

## start

    $server->start;

Starts the MySQL database instance.

## stop

    $server->stop;

Stops the MySQL database instance.

## is\_up

    my $bool = $server->is_up;

Checks to see if the MySQL database instance is up.

## list\_databases

    my @names = $server->list_databases;

Returns a list of the databases on the MySQL instance.

## create\_database

    $server->create_database($dbname);

Create a new database with the given name.

## drop\_database

    $server->drop_database($dbname);

Drop database with the given name.

## interactive\_shell

    $server->interactive_shell($dbname);
    $server->interactive_shell;

Connect to the database using an interactive shell.

## load

    $server->load($dbname, $sql, \@options);

Connect to the database using a non-interactive shell.

- `$dbname`

    The name of the database

- `$sql`

    The SQL to execute.

- `\@options`

    The `mysql` options to use.

## dsn

    my $dsn = $server->dsn($driver, $dbname);
    my $dsn = $server->dsn($driver);
    my $dsn = $server->dsn;

Provide a DSN that can be fed into DBI to connect to the database using [DBI](https://metacpan.org/pod/DBI).  These drivers are supported: [DBD::Pg](https://metacpan.org/pod/DBD::Pg), [DBD::PgPP](https://metacpan.org/pod/DBD::PgPP), [DBD::PgPPSjis](https://metacpan.org/pod/DBD::PgPPSjis).

## dump

    $server->dump($dbname => $dest, %options);
    $server->dump($dbname => $dest, %options, \@native_options);

Dump data and/or schema from the given database.  If `$dbname` is `undef`
then the `mysql` database will be used.  `$dest` may be either
a filename, in which case the dump will be written to that file, or a
scalar reference, in which case the dump will be written to that scalar.
Native `pg_dump` options can be specified using `@native_options`.
Supported [Database::Server](https://metacpan.org/pod/Database::Server) options include:

- data

    Include data in the dump.  Off by default.

- schema

    Include schema in the dump.  On by default.

- access

    Include access controls in the dump.  Off by default.
    Not currently supported.

# AUTHOR

Graham Ollis &lt;plicease@cpan.org>

# COPYRIGHT AND LICENSE

This software is copyright (c) 2015 by Graham Ollis.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

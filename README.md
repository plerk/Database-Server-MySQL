# Database::Server::MySQL

Interface for MySQL server instance

# SYNOPSIS

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

# METHODS

## create

    $server->create;

Create the MySQL instance.  This involves calling `mysqld --initalize` or
`mysql_install_db` with the appropriate options to produce the data files
necessary for running the MySQL server instance.

## start

    $server->start;

Starts the MySQL database instance.

## stop

    $server->stop;

Stops the MySQL database instance.

## is\_up

    my $bool = $server->is_up;

Checks to see if the MySQL database instance is up.

# AUTHOR

Graham Ollis &lt;plicease@cpan.org>

# COPYRIGHT AND LICENSE

This software is copyright (c) 2015 by Graham Ollis.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

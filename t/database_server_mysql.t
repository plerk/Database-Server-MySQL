use strict;
use warnings;
use Test::More tests => 2;
use Database::Server::MySQL;
use File::Temp qw( tempdir );
use Path::Class qw( dir );
use IO::Socket::IP;
use Config::INI::Reader;

subtest 'normal' => sub {

  plan tests => 8;

  my $data = dir( tempdir( CLEANUP => 1 ) );
  my $server  = Database::Server::MySQL->new(
    data        => $data->subdir('data'),
    pid_file    => $data->file('mysql.pid'),
    port        => IO::Socket::IP->new(Listen => 5, LocalAddr => '127.0.0.1')->sockport,
    socket      => $data->file('mysql.sock'),
    log_error   => $data->file('mysql_error.log'),
    mylogin_cnf => $data->file('mylogin.cnf'),
  );
  isa_ok $server, 'Database::Server::MySQL';
  
  $server->data->mkpath(0,0700);

  subtest init => sub {
    plan tests => 2;
    my $ret = eval { $server->init };
    is $@, '', 'creating server did not crash';
 
    note "% @{ $ret->command }";
    note "[out]\n@{[ $ret->out ]}" if $ret->out ne '';
    note "[err]\n@{[ $ret->err ]}" if $ret->err ne '';
    note "[exit]@{[ $ret->exit ]}";
  
    ok $ret->is_success, 'init database';
  };

  subtest myloging_cnf => sub {
    plan tests => 5;
    ok -r $server->mylogin_cnf, 'created mylogin_cnf';
    my $config = eval { Config::INI::Reader->read_file($server->mylogin_cnf) };
    is $@, '', 'no error on read';
    
    is $config->{client}->{port},   $server->port,   'port matches';
    is $config->{client}->{socket}, $server->socket, 'socket matches';
    # TODO support binding to particular IP
    is $config->{client}->{host},   '127.0.0.1',     'host matches';
  };
  
  # This isn't workable since MYSQL_TEST_LOGIN_FILE is not supported
  # by MariaDB
  #subtest env => sub {
  #  plan tests => 1;
  #  my %env = $server->env;
  #  is $env{MYSQL_TEST_LOGIN_FILE}, "@{[ $data->file('mylogin.cnf') ]}", "MYSQL_TEST_LOGIN_FILE";
  #};

  is $server->is_up, '', 'server is down before start';
  
  subtest start => sub {
    plan tests => 2;
    my $ret = eval { $server->start };
    is $@, '', 'start server did not crash';

    ok($ret->is_success, 'started database')
      || diag
        "=== log_error ===\n",
        $server->log_error->slurp,
        "--- log_error ---\n";

    note "[out]\n@{[ $ret->out ]}" if $ret->out ne '';
    note "[err]\n@{[ $ret->err ]}" if $ret->err ne '';
    note "[exit]@{[ $ret->exit ]}";

  };

  is $server->is_up, 1, 'server is up after start';
  note "pid = ", (eval { $server->pid_file->slurp } // 'no pid file');

  subtest stop => sub {
    plan tests => 2;
    my $ret = eval { $server->stop };
    is $@, '', 'stop server did not crash';
    
    note "[message]\n@{[ $ret->message ]}" if $ret->message;    

    ok $ret->is_success, 'stop database';
  };
 
  is $server->is_up, '', 'server is down after stop';
};

subtest 'try to init server with existing data directory' => sub {
  plan tests => 1;
  my $data = dir( tempdir( CLEANUP => 1 ) );
  $data->subdir('data')->mkpath(0,0700);
  $data->file('data', 'roger.txt')->spew('anything');

  my $server  = Database::Server::MySQL->new(
    data      => $data->subdir('data'),
    pid_file  => $data->file('mysql.pid'),
    port      => IO::Socket::IP->new(Listen => 5, LocalAddr => '127.0.0.1')->sockport,
    socket    => $data->file('mysql.sock'),
    log_error => $data->file('mysql_error.log'),
  );

  eval { $server->init };
  like $@, qr{^$data/data is not empty}, 'died with correct exception';
};

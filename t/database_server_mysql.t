use strict;
use warnings;
use Test::More tests => 2;
use Database::Server::MySQL;
use File::Temp qw( tempdir );
use Path::Class qw( dir );
use IO::Socket::IP;

subtest 'normal' => sub {
  my $data = dir( tempdir( CLEANUP => 1 ) );
  my $server  = Database::Server::MySQL->new(
    data      => $data->subdir('data'),
    pid_file  => $data->file('mysql.pid'),
    port      => IO::Socket::IP->new(Listen => 5, LocalAddr => '127.0.0.1')->sockport,
    socket    => $data->file('mysql.sock'),
    log_error => $data->file('mysql_error.log'),
  );
  isa_ok $server, 'Database::Server::MySQL';
  
  $server->data->mkpath(0,0700);

  subtest create => sub {
    plan tests => 2;
    my $ret = eval { $server->create };
    is $@, '', 'creating server did not crash';
 
    note "% @{ $ret->command }";
    note "[out]\n@{[ $ret->out ]}" if $ret->out ne '';
    note "[err]\n@{[ $ret->err ]}" if $ret->err ne '';
    note "[exit]@{[ $ret->exit ]}";
  
    ok $ret->is_success, 'created database';
  };

  is $server->is_up, '', 'server is down before start';
  
  subtest start => sub {
    plan tests => 2;
    my $ret = eval { $server->start };
    is $@, '', 'start server did not crash';

    note "[message]\n@{[ $ret->message ]}" if $ret->message;    

    ok $ret->is_success, 'started database';
  };

  is $server->is_up, 1, 'server is up after start';
  note "pid = ", $server->pid_file->slurp;

  subtest stop => sub {
    plan tests => 2;
    my $ret = eval { $server->stop };
    is $@, '', 'stop server did not crash';
    
    note "[message]\n@{[ $ret->message ]}" if $ret->message;    

    ok $ret->is_success, 'stop database';
  };
 
  is $server->is_up, '', 'server is down after stop';
};

subtest 'try to create server with existing data directory' => sub {
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

  eval { $server->create };
  like $@, qr{^$data/data is not empty}, 'died with correct exception';
};

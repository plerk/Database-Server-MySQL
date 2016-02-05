use strict;
use warnings;
use Test::More tests => 2;
use Database::Server::MySQL;
use File::Temp qw( tempdir );
use Path::Class qw( dir );
use IO::Socket::IP;
use Config::INI::Reader;

subtest 'normal' => sub {

  plan tests => 11;

  my $data = dir( tempdir( CLEANUP => 1 ) );
  my $server  = Database::Server::MySQL->new(
    data        => $data->subdir('data'),
    pid_file    => $data->file('mysql.pid'),
    port        => IO::Socket::IP->new(Listen => 5, LocalAddr => '127.0.0.1')->sockport,
    socket      => $data->file('mysql.sock'),
    log_error   => $data->file('mysql_error.log'),
    mylogin_cnf => $data->file('mylogin.cnf'),
    skip_grant_tables => 1,
    #skip_networking   => 1,
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

  subtest 'create/drop/list' => sub {
    plan tests => 5;
  
    eval { $server->create_database('foo') };
    is $@, '', 'server.create_database';
    
    my %list = map { $_ => 1 } eval { $server->list_databases };
    is $@, '', 'server.list_databases';
    ok $list{foo}, 'database foo exists';
    
    note "databases:";
    note "  $_" for keys %list;
    
    eval { $server->drop_database('foo') };
    is $@, '', 'server.drop_database';
    
    %list = map { $_ => 1 } eval { $server->list_databases };
    ok !$list{foo}, 'database foo does not exist';
  
  };

  subtest 'shell/dsn' => sub {
  
    plan tests => 2;
  
    my $dbname = 'foo1';
    eval { $server->create_database($dbname) };
    diag $@ if $@;
    my $sql = q{
      CREATE TABLE bar (baz VARCHAR(900));
      INSERT INTO bar VALUES ('hi there');
    };
  
    my $ret = eval { $server->shell($dbname, $sql, []) };
    is $@, '', 'server.shell';

    note "[out]\n@{[ $ret->out ]}" if $ret->out ne '';
    note "[err]\n@{[ $ret->err ]}" if $ret->err ne '';
    note "[exit]@{[ $ret->exit ]}";

    foreach my $driver (qw( mysql ))
    {
      subtest "DBD::$driver" => sub {
        plan skip_all => "test requires DBD::$driver" unless eval qq{ use DBI; use DBD::$driver; 1 };
        plan tests => 2;
        my $dsn = eval { $server->dsn($driver, $dbname) };
        is $@, '', "server.dsn($driver, $dbname)";
        note "dsn=$dsn";
        my $value = eval {
          my $dbh = DBI->connect($dsn, '', '', { RaiseError => 1, AutoCommit => 1 });
          my $sth = $dbh->prepare(q{ SELECT baz FROM bar });
          $sth->execute;
          $sth->fetchrow_hashref->{baz};
        };
        is $value, 'hi there', 'query good';
      };
    }
  
  };

  subtest dump => sub {
    plan tests => 6;
    $server->create_database('dumptest1');
    $server->shell('dumptest1', "CREATE TABLE foo (id int); INSERT INTO foo (id) VALUES (22);");

    my $dump = '';
    $server->dump('dumptest1', \$dump, data => 0, schema => 1);
    isnt $dump, '', 'there is a dump (schema only)';
    
    $server->create_database('dumptest_schema_only');
    $server->shell('dumptest_schema_only', $dump);

    $dump = '';
    $server->dump('dumptest1', \$dump, data => 1, schema => 1);
    isnt $dump, '', 'there is a dump (data only)';

    $server->create_database('dumptest_schema_and_data');
    $server->shell('dumptest_schema_and_data', $dump);
    
    my $dbh = eval {
      DBI->connect($server->dsn('mysql', 'dumptest_schema_only'), '', '', { RaiseError => 1, AutoCommit => 1 });
    };
    
    SKIP: {
      skip "test requires DBD::mysql $@", 4 unless $dbh;
      
      my $h = eval {
        my $sth = $dbh->prepare(q{ SELECT * FROM foo });
        $sth->execute;
        $sth->fetchrow_hashref;
      };
      is $@, '', 'did not crash';
      is $h, undef, 'schema only';
      
      $dbh = DBI->connect($server->dsn('mysql', 'dumptest_schema_and_data'), '', '', { RaiseError => 1, AutoCommit => 1 });
      
      $h = eval {
        my $sth = $dbh->prepare(q{ SELECT * FROM foo });
        $sth->execute;
        $sth->fetchrow_hashref;
      };
      is $@, '', 'did not crash';
      is_deeply $h, { id => 22 }, 'schema only';

    };
    
  };

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

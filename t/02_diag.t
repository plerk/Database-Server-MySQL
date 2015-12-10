use strict;
use warnings;
use Test::More tests => 1;
use File::Which qw( which );
use Capture::Tiny qw( capture );

my $mysqld = which('mysqld') // which('/usr/sbin/mysqld');
my $mysql  = which('mysql');

diag '';
diag '';
diag '';

diag 'mysqld = ', $mysqld;
diag '       : ', [split /\r?\n/, capture { system $mysqld, '--version' }]->[0];
diag 'mysql  = ', $mysql;
diag '       : ', [split /\r?\n/, capture { system $mysql, '--version' }]->[0];

diag '';
diag '';

pass 'good';

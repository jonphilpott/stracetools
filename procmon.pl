#!/usr/bin/perl
#
# Monitors processes in /proc, can:
# a) output process state in CSV
# b) insert into a sqlite database.
#
# All processes will be traced or you can choose to trig on a
# particular state.

use strict; 
use POSIX qw(strftime);
use DBI;
use Getopt::Long;


my $TRIGGER_MODE = 0;
my $TRIGGER_STATE = 'D';

my $INTERVAL_TIME = 1;

# 0 -> CSV file to stdout
# 1 -> sqlite database
my $OUTPUT_MODE = 0;

# sqlite filename
my $SQLITE_FILENAME = "ps.db";

my $HELP;

GetOptions('trigger|t'           => \$TRIGGER_MODE,
           'trigger-state|s=s'   => \$TRIGGER_STATE,
           'interval|i=s'        => \$INTERVAL_TIME,
           'sqlmode|m'           => \$OUTPUT_MODE,
           'dbfile|d=s'          => \$SQLITE_FILENAME,
           'help|h'              => \$HELP,
          );

if ($HELP) {
    print <<'USAGE';
usage: procmon.pl --trigger|t --trigger-state|s --interval|i --sqlmode|m --dbfile|d --help|h
--trigger, -t: Trigger mode, only output when process state is a certain value, default is OFF
--trigger-state, -s: Process state to trigger on, default is "D"
--interval, -i: how often to refresh, default is 1 (second)
--sqlmode, -m: Instead of CSV output to STDOUT, output to sqlite3 db
--dbfile, -d: sqlite3 filename
--help, -h: duh.

USAGE
    exit;
}

my %WANT_FIELDS = 
  (Name    => 1,
   State   => 1,
   Pid     => 1,
   Uid     => 1,
   Gid     => 1,
   VmSize  => 1,
   VmPeak  => 1,
   VmRSS   => 1,
   VmData  => 1,
   VmStk   => 1,
   VmExe   => 1,
   VmLib   => 1,
   VmSwap  => 1,
   Threads => 1,
  );

use constant COMMIT_LIMIT => 500;

sub get_handle {
    my ($filename) = @_;
    return DBI->connect("dbi:SQLite:$filename","","",
                        { AutoCommit => 0 });
}

sub create_table {
    my ($dbh) = @_;

    $dbh->do(<<'CREATE_TABLE');
CREATE TABLE ps
(id       integer primary key,
 pid      varchar(8),
 start    time,
 name     varchar(32),
 state    varchar(1),
 uid      integer,
 gid      integer,
 vmsize   integer,
 vmpeak   integer,
 vmrss    integer,
 vmdata   integer,
 vmstk    integer,
 vmexe    integer,
 vmlib    integer,
 vmswap   integer,
 threads  integer,
 wchan    varchar(64)
);
CREATE_TABLE
}


my $insert_handle;
sub prepare_insert {
    my ($dbh) = @_;

    $insert_handle = $dbh->prepare(<<'INSERT_QUERY');
INSERT INTO ps (pid, start, name, state, uid, gid, vmsize, vmpeak, vmrss, vmdata, vmstk, vmexe, vmlib, vmswap, threads, wchan)
VALUES  (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?);
INSERT_QUERY

    return $insert_handle;
}


sub insert_row {
    my ($sth, $info) = @_;

    $sth->execute(@{$info}{qw(Pid Time Name State Uid Gid 
                              VmSize VmPeak VmRSS VmData VmStk VmExe VmLib VmSwap 
                              Threads Wchan)});

}

sub csv_output {
    my ($info) = @_;
    print join(",", @{ $info }{qw(Time Pid Name State Uid Gid VmSize VmPeak Threads Wchan)}), "\n";
}

sub main {
    my ($output) = @_;

    while (1) {
        opendir(my $dh, "/proc") || die "Couldn't open /proc $!";
        
        while (readdir $dh) {
            next unless /^\d+$/; # only pids please.
            my $pid = $_;
            
            open(my $sfh, join("/", "/proc", $pid, "status")) || next;
            my %info = (
                Time => time,
               );
            
            while(<$sfh>) {
                chomp;
                /^(.+):\s+(.+)/;
		my $key = $1;
		my $value = $2;
		$value =~ s/\t/ /g;
                $info{$key} = $value 
                  if (exists $WANT_FIELDS{$key});
            }
            close($sfh);
            
            open(my $wfh, join("/", "/proc", $pid, "wchan")) || next;
            $info{Wchan} = <$wfh>;
            close($wfh);
            
            if (!$TRIGGER_MODE || ($TRIGGER_MODE && $TRIGGER_STATE eq $info{State})) {
                &{ $output }(\%info);
            }
        }
        
        close($dh);
        sleep $INTERVAL_TIME;
    }
}

if ($OUTPUT_MODE) {
    my $dbh = get_handle($SQLITE_FILENAME) || die "Could not open sqlite database.";

    create_table($dbh);

    my $prepare_handle = prepare_insert($dbh);
    
    # commit signal handler
    $SIG{'INT'} = sub {
        $dbh->commit;
        exit(1);
    };

    my $commit_count = 0;
    main(sub {
             my ($info) = @_;
             insert_row($prepare_handle, $info);
             if ($commit_count++ > COMMIT_LIMIT) {
                 $dbh->commit;
                 $commit_count = 0;
             }
         });
}
else {
    main(\&csv_output);
}

#!/usr/bin/perl
#
# Monitors processes in /proc, can:
# a) output process state in CSV
# b) insert into a sqlite database.
#
# All processes will be traced or you can choose to trigger on
# particular states


use strict; 
use Data::Dumper;

my $TRIGGER_MODE = 0;
my $TRIGGER_STATES = qw(D Z);

# 0 -> CSV file to stdout
# 1 -> sqlite database
my $OUTPUT_MODE = 0;

# sqlite filename
my $SQLITE_FILENAME = "ps.db";

opendir(my $dh, "/proc") || die "Couldn't open /proc $!";

my @WANT_FIELDS = 
  qw(Name
     State
     Pid
     Uid
     Gid
     VmSize
     VmPeak
     Threads
   );
                   
while(readdir $dh) {
    next unless /^\d+$/; # only pids please.
    my $pid = $_;

    open(my $sfh, join("/", "/proc", $pid, "status")) || next;
    my %info;
    while(<$sfh>) {
        chomp;
        /^(.+):\s+(.+)$/;
        $info{$1} = $2;
    }
    close($sfh);

    open(my $wfh, join("/", "/proc", $pid, "wchan")) || next;
    $info{Wchan} = <$wfh>;
    close($wfh);

    print Dumper(\%info);
}

close($dh);

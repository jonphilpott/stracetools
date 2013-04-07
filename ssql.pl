#!/usr/bin/perl
# Script to convert various strace outputs into a sqlite3 database

use strict;
use DBI;

use constant COMMIT_LIMIT => 1000;

sub get_handle {
    my $filename = $_[0];
    return DBI->connect("dbi:SQLite:$filename","","",
                       { AutoCommit => 0 });
}

sub strip {
    my $text = $_[0];
    $text =~ s/\s+$//;
    return  $text;
}

sub parse1 {
    $_ = $_[0];
    # case 1 - strace output to file. with -f
    if (/^(\d+) (\d\d:\d\d:\d\d).(\d+) (.+)/) {
        return ($1, $2, $3, $4);
    }
    # case 2 - strace to stdout with -f and a child pid.
    elsif (/^\[pid (\d+)\] (\d\d:\d\d:\d\d).(\d+) (.+)/) {
        return ($1, $2, $3, $4);
    }
    # case 3 strace to stdout with parent pid or not -f
    elsif (/^(\d\d:\d\d:\d\d).(\d+) (.+)/) {
        return ('parent', $1, $2, $3);
    }
    else {
        warn "Unrecognised input - are you running strace with -Ttt?";
    }
}

sub parse2 {
    $_ = $_[0];

    if (/^(\w+)\((.+)?= (.+) <([0-9.]+)>$/) {
        return  ($1, $1."(".strip($2), $3, $4);
    }
    else {
        return ("", $_, "", "");
    }
}

sub create_table {
    my $dbh = shift;

    $dbh->do(<<'EOT');
CREATE TABLE strace
(id integer primary key,
 pid   varchar(8),
 start time,
 mili  integer,
 syscall text,
 full text,
 ret text,
 dur real);
EOT

}

sub main {
    my $dbh = shift;

    my $sth = $dbh->prepare("INSERT INTO strace (pid, start, mili, syscall, full, ret, dur) VALUES (?, ?, ?, ?, ?, ?, ?);");
    $sth->execute();

    my $n = 0;
    while (<STDIN>) {
        chomp;
        my ($pid, $time, $mili, $base) = parse1($_);
        next unless $pid;
        my ($syscall, $text, $ret, $dur) = parse2($base);
        next unless $text;
        $sth->execute($pid, $time, $mili, $syscall, $text, $ret, $dur);
        if ($n++ > COMMIT_LIMIT) {
            $n = 0; $dbh->commit;
        }
    }
    $dbh->commit;
}


my $dbh = get_handle($ARGV[0] ? $ARGV[0] : 'strace.db');
die "Could not open sqlite database." unless $dbh;

create_table($dbh) && main($dbh);


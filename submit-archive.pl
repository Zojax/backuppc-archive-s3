#!/usr/bin/perl -T
#
# Quick hack to submit an archive request to the BackupPC daemon from the
# command line. Note that this script probably needs to be run as user
# 'backuppc' (or whatever the BackupPC user is on your system) in order to
# be able to view the pool.
# This is meant as a proof of concept, not as an example for beautiful Perl
# code. USE AT OWN RISK!
# Note that excerpts of the code are taken from BackupPC via a discussion
# on the backuppc-users mailing list, so this code is probably GPL too. Can't
# hurt in any case :).
# Hacked together by Holger Parplies after detailed BackupPC code analysis by
# Timothy J. Massey.
# Please change the two paths in the next block to match your setup.

#use strict;
use lib '/usr/share/backuppc/lib'; # Debian; change to fit your needs
use BackupPC::Lib;
use Getopt::Std;
use constant BACKUPPCBINDIR => '/usr/share/backuppc/bin'; # Debian; change ...

# All changes required below here are due to bugs :).

$ENV {PATH} = '/bin:/usr/bin';  # for taint checking / system (which doesn't
                                # use the path)
my %opts = (
            a => 'archive',     # archive host
            h => 'localhost',   # list of hosts to archive
            n => '-1',          # list of backup numbers to archive
            o => '/var/lib/backuppc/removable', # output destination
            u => 'backuppc',    # BackupPC user to run the archive command as
# Adding options, part 1: add X => 'default value' here
           );

# Adding options, part 2: add X: in the first argument to getopts() and,
# preferably, the usage note
unless (getopts ('a:h:n:o:u:', \%opts)) {
    die "Usage: $0 [-a archivehost] [-h hostlist] [-n numlist] [-o outloc] [-u 
user]\n";
    # I *had* a more descriptive message, before writing to a group writable
    # setuid script deleted my first attempt. *sigh*
}

# some variables
my @hosts = split /[:,\/]/, $opts {h}; # array of hosts
my @nums  = split /[:,\/]/, $opts {n}; # array of backup numbers
my $hostlist;                   # textual list of hosts
my $numlist;                    # textual list of backup numbers
my $reqtime = time;             # timestamp
my $bpc = new BackupPC::Lib
    or die "Can't create BackupPC object!\n";
my $topdir = $bpc -> {TopDir};  # shorthand for TopDir
my $rfn;                        # request file name
my $frfn;                       # full request file name (with path)
my %backups;                    # backup info indexed by host name

# clone host or backup number if appropriate
@hosts = map { $hosts [0] } (1 .. @nums)
  if @hosts == 1 and @nums  > 1;
@nums  = map { $nums  [0] } (1 .. @hosts)
  if @nums  == 1 and @hosts > 1;

# complain if params are unmatched or missing
if (@hosts != @nums or @hosts == 0) {
  die "Hey, you need matching host and backup number specifications or only\n"
    . "one of either!\n";
}

# translate backup numbers if negative, check for existing hosts and backups
for (my $i = 0; $i < @nums; $i ++) {
  if (not -d "$topdir/pc/$hosts[$i]") {
    die "Host $hosts[$i] does not exist!\n";
  }
  $backups {$hosts [$i]} = [ $bpc -> BackupInfoRead ($hosts [$i]) ]
    unless exists $backups {$hosts [$i]};
  $nums [$i] = $backups {$hosts [$i]} [$nums [$i]] {num}
    if $nums [$i] < 0 and -$nums [$i] <= @{$backups {$hosts [$i]}};
  if (not grep {$_ -> {num} == $nums [$i]} @{$backups {$hosts [$i]}}) {
    die "There is no backup $nums[$i] of host $hosts[$i]!\n";
  }
}
$hostlist = '"' . join ('", "', @hosts) . '"';
$numlist  = '"' . join ('", "', @nums)  . '"';

# untaint archive host name
if ($opts {a} =~ m{^([^/]+)$}) {
  $opts {a} = $1;
} else {
  die "Archive host name '$opts{a}' invalid!\n";
}

# check whether the archive hosts at least apparently exists
unless (-d "$topdir/pc/$opts{a}") {
  die "The archive host $opts{a} does not exist or the pool is corrupt!\n";
}

# create new request file (without thinking too much about security :)
for (my $i = 0; ; $i ++) {
  $rfn = "archiveReq.$$.$i"; $frfn = "$topdir/pc/$opts{a}/$rfn";
  last
    unless -f $frfn;
}
open REQF, ">$frfn"
  or die "Can't create request file $frfn: $!\n";
# Adding options, part 3: use $opts{X} presumably in here ...
print REQF <<EOREQ;
\%ArchiveReq = (
   'archiveloc' => '$opts{o}',
   'reqTime' => '$reqtime',
   'BackupList' => [
     $numlist
   ],
   'host' => '$opts{a}',
   'parfile' => '5',
   'archtype' => '0',
   'compression' => '/bin/cat',
   'compext' => '.raw',
   'HostList' => [
     $hostlist
   ],
   'user' => $opts {u},
   'splitsize' => '0000000'
);

EOREQ
close REQF;

# submit request to the BackupPC daemon
system (BACKUPPCBINDIR . '/BackupPC_serverMesg',
        'archive', $opts {u}, $opts {a}, $rfn);

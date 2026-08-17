#!/usr/bin/env perl
# tmo.pl — a portable `timeout(1)`: run a command under a wall-clock cap.
#
#   perl tests/lib/tmo.pl <seconds> <command> [args...]
#
# Exit codes follow coreutils: 124 when the cap fires, otherwise the command's
# own exit status (127 when it cannot be executed at all).
#
# WHY THIS EXISTS. `eval-local-first-behavior.sh` documents a 600s cap per
# scenario and resolved it as timeout -> gtimeout -> **run bare**. macOS ships
# neither binary, so on the machine this repo is developed on the documented cap
# did not exist: a headless `claude -p` that never returns hung indefinitely,
# indistinguishable from a slow one. Perl is present on macOS and on every Linux
# this suite plausibly runs on, so this fallback cannot itself be absent — which
# is the whole point. A guard with a branch that silently does nothing is the
# failure mode, not the platform.
use strict;
use warnings;

die "usage: tmo.pl <seconds> <command> [args...]\n" if @ARGV < 2;
my $secs = shift @ARGV;
die "tmo.pl: <seconds> must be a positive number\n" unless $secs =~ /^\d+(\.\d+)?$/ && $secs > 0;

my $pid = fork();
die "tmo.pl: fork failed: $!\n" unless defined $pid;

if ($pid == 0) {
    # exec replaces the child; reaching the next line means it could not run.
    exec { $ARGV[0] } @ARGV;
    exit 127;
}

my $timed_out = 0;
$SIG{ALRM} = sub {
    $timed_out = 1;
    # The whole process group, not just the child: a shell wrapper that has
    # already forked leaves the real worker running, and killing only the
    # wrapper returns 124 while the command keeps going.
    kill 'KILL', -$pid or kill 'KILL', $pid;
};
alarm $secs;
waitpid($pid, 0);
my $status = $?;
alarm 0;

exit 124 if $timed_out;
exit($status >> 8);

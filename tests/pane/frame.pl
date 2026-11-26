#!/usr/bin/perl
# tests/pane/frame.pl <cols> < frame: reads one `tmux capture-pane -e -p` frame of a Claude Code terminal
# and prints what the pane harness judges, one key=value per line:
#   open      1 when a Claude Code pane is drawn (its close mark, ✕, is on screen), else 0
#   ring      the text under the focus ring (inverse video), spans joined by " | "; empty for none
#   hint      the pane's key line, or empty: the first line holding "Esc close", "Esc back", "c close",
#             "b back", or "working: " (what a key started, while it runs)
#   top       the column the pane's top frame starts at, and topend where it ends (-1 when not found)
#   dock      1 when the pane sits in a column beside the conversation (its frame starts right of 0)
#   agents    1 when Claude Code's background agents view is on screen instead of the prompt
#   bold      the bold spans inside the pane, joined by " | " (the selected task's row is bold)
#   text      every line of the frame with the escapes removed, as text=<line>, last
use strict;
use warnings;
use utf8;
binmode STDIN, ':encoding(UTF-8)';
binmode STDOUT, ':encoding(UTF-8)';

my $cols = shift // 80;
my @raw = <STDIN>;
my (@plain, @rings, @bolds);
for my $line (@raw) {
    chomp $line;
    my ($on, $buf, $out, $bon, $bbuf) = (0, '', '', 0, '');
    for my $tok (split /(\e\[[0-9;?]*[A-Za-z])/, $line) {
        if ($tok =~ /^\e\[([0-9;]*)m$/) {
            my @codes = length $1 ? split(/;/, $1) : ('0');
            my %c = map { $_ => 1 } @codes;
            if ($c{7}) { $on = 1 }
            if ($c{1}) { $bon = 1 }
            if ($c{27} || $c{0}) { push @rings, $buf if $on && $buf =~ /\S/; $on = 0; $buf = '' }
            if ($c{22} || $c{0}) { push @bolds, $bbuf if $bon && $bbuf =~ /\S/; $bon = 0; $bbuf = '' }
            next;
        }
        next if $tok =~ /^\e/;
        $out .= $tok;
        $buf .= $tok if $on;
        $bbuf .= $tok if $bon;
    }
    push @rings, $buf if $on && $buf =~ /\S/;
    push @bolds, $bbuf if $bon && $bbuf =~ /\S/;
    push @plain, $out;
}
s/^\s+|\s+$//g for @rings, @bolds;
# The pane marks the selection with "›" as text too; the rules judge the ring and the labels without it.
s/› //g for @rings, @bolds, @plain;

my $open = (grep { /✕/ } @plain) ? 1 : 0;
# A docked pane shares each line with the conversation to its left; the pane's part starts after the rule.
my $dockcol = -1;
for my $l (@plain) { if ($l !~ /╭/ && $l =~ /✕/ && $l =~ /^(.+?)│/) { $dockcol = length $1; last } }
my @pane = map { $dockcol >= 0 && length($_) > $dockcol ? substr($_, $dockcol + 1) : $_ } @plain;
my ($hint) = grep { /(Esc close|Esc leaves|Esc back|c close|b back|working: )/ } @pane;
$hint //= '';
$hint =~ s/^[│\s]+|[│\s]+$//g;
my ($top, $topend, $dock) = (-1, -1, 0);
for my $l (@plain) {
    if ($l =~ /^(.*?)╭.*╮/) {
        $top = length $1;
        $topend = rindex($l, '╮');
        last;
    }
}
# A docked pane has no rounded top corner: its frame is a vertical rule beside the conversation, with the
# close mark at the right of its first row.
if ($open && $top < 0) {
    # The capture is taken from the last match made, so the close mark is matched first.
    for my $l (@plain) { if ($l =~ /✕/ && $l =~ /^(.+?)│/) { $dock = 1; $top = length $1; last } }
}
my $agents = (grep { /enter to return/ } @plain) ? 1 : 0;

print "open=$open\n";
print 'ring=', join(' | ', @rings), "\n";
print 'bold=', join(' | ', @bolds), "\n";
print "hint=$hint\n";
print "top=$top\ntopend=$topend\ndock=$dock\nagents=$agents\n";
print "text=$_\n" for @plain;

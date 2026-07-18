#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../app/src/main/assets/perl";
use Asciitrek::Engine;
use Time::HiRes qw(sleep);

my $columns = $ENV{COLUMNS} || 100;
my $rows = $ENV{LINES} || 30;
my $engine = Asciitrek::Engine->new(
    columns => $columns, rows => $rows, seed => ($ENV{ASCIITREKPAPER_SEED} || time),
    event => ($ENV{ASCIITREK_SHIP} || 'enterprise'),
    direction => ($ENV{ASCIITREK_DIRECTION} || ''),
    battle => ($ENV{ASCIITREK_BATTLE} || ''),
);

my @ansi = (0, 97, 96, 92, 94, 95, 93, 91);
$SIG{INT} = sub { print "\e[0m\e[?25h\n"; exit };
print "\e[2J\e[?25l";
while (1) {
    my $frame = $engine->tick_frame(.05);
    print "\e[H";
    for my $row (0 .. $rows - 1) {
        my $active = -1;
        for my $column (0 .. $columns - 1) {
            my $offset = ($row * $columns + $column) * 2;
            my ($glyph, $color) = unpack('CC', substr($frame, $offset, 2));
            if ($color != $active) {
                print $color ? "\e[$ansi[$color]m" : "\e[0m";
                $active = $color;
            }
            print chr($glyph);
        }
        print "\e[0m\n";
    }
    sleep(.05);
}

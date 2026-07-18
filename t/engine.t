use strict;
use warnings;
use Test::More;

use lib 'app/src/main/assets/perl';
use Asciitrek::Engine;

sub entities_of_type {
    my ($engine, $type) = @_;
    return grep { $_->{type} eq $type } @{$engine->debug_entities};
}

sub advance {
    my ($engine, $seconds) = @_;
    while ($seconds > 0) {
        my $step = $seconds > .1 ? .1 : $seconds;
        $engine->tick($step);
        $seconds -= $step;
    }
}

my $engine = Asciitrek::Engine->new(
    columns => 100, rows => 30, seed => 7,
    event => 'enterprise', direction => 'left',
);
is_deeply([$engine->dimensions], [100, 30], 'engine uses requested terminal grid');
is(length($engine->frame_bytes), 100 * 30 * 2, 'frame contains glyph/color pair per cell');

my $counts = $engine->entity_counts;
is($counts->{enterprise}, 1, 'default forced flyby is Enterprise');
is($counts->{planet}, 1, 'planetary system is present');
for my $layer (0 .. 3) {
    ok($counts->{"star_layer_$layer"}, "star depth layer $layer is populated");
}

my @star_speed;
my @twinkle_rate;
for my $layer (0 .. 3) {
    my @stars = entities_of_type($engine, "star_layer_$layer");
    $star_speed[$layer] = abs($stars[0]{vx});
    $twinkle_rate[$layer] = $stars[0]{frame_rate};
    ok($stars[0]{vx} < 0, "star layer $layer scrolls right-to-left");
    ok($stars[0]{frame_rate} > 0, "star layer $layer twinkles");
}
for my $layer (1 .. 3) {
    cmp_ok(abs($star_speed[$layer] / $star_speed[$layer - 1] - .8), '<', .00001,
        "star layer $layer is 20% slower than the layer in front");
}

my ($enterprise) = entities_of_type($engine, 'enterprise');
cmp_ok($enterprise->{vx}, '<', 0, 'forced left Enterprise travels left');
cmp_ok(abs(abs($enterprise->{vx}) - .264), '<', .00001,
    'Enterprise preserves the globally accelerated CLI speed');

my $klingon = Asciitrek::Engine::klingon_brel_art();
my $mirrored = $engine->mirror_ascii($klingon);
my $round_trip = $engine->mirror_ascii($mirrored);
my @padded = split /\n/, $klingon, -1;
my $width = 0;
for my $line (@padded) { $width = length($line) if length($line) > $width }
$_ .= ' ' x ($width - length($_)) for @padded;
is($round_trip, join("\n", @padded), 'directional mirroring preserves padded artwork exactly');

my @events = (
    [enterprise => 'enterprise'], [borg => 'borg_cube'], [klingon => 'klingon'],
    [romulan => 'romulan'], [comet => 'comet'], [wormhole => 'wormhole'],
);
for my $event (@events) {
    my $scene = Asciitrek::Engine->new(columns => 100, rows => 30, seed => 9,
        event => $event->[0], direction => 'right');
    ok($scene->entity_counts->{$event->[1]}, "$event->[0] event uses the expected entity");
    is(length($scene->frame_bytes), 6000, "$event->[0] event renders a complete frame");
}

my $borg = Asciitrek::Engine->new(columns => 100, rows => 30, seed => 3,
    event => 'borg', direction => 'right');
my ($cube) = entities_of_type($borg, 'borg_cube');
is_deeply([$cube->{width}, $cube->{height}], [22, 10], 'Borg cube keeps corrected terminal dimensions');

my $romulan = Asciitrek::Engine->new(columns => 100, rows => 30, seed => 3,
    event => 'romulan');
my ($warbird) = entities_of_type($romulan, 'romulan');
is($warbird->{vx}, 0, 'front-profile Romulan warbird does not slide sideways');
cmp_ok($warbird->{frame_rate}, '>', 0, 'Romulan approach/recede profile animates');

my $wormhole = Asciitrek::Engine->new(columns => 100, rows => 30, seed => 3,
    event => 'wormhole');
my ($anomaly) = entities_of_type($wormhole, 'wormhole');
cmp_ok($anomaly->{vx}, '<', 0, 'wormhole participates in background drift');
cmp_ok($anomaly->{frame_rate}, '>', 0, 'wormhole rotates');

my $battle = Asciitrek::Engine->new(columns => 100, rows => 30, seed => 12,
    event => 'battle', battle => 'federation,klingon');
$counts = $battle->entity_counts;
is($counts->{battle_galaxy_class}, 1, 'forced battle contains Federation Galaxy class');
is($counts->{battle_brel_class}, 1, 'forced battle contains Klingon Brel class');
ok(!$counts->{planet}, 'battle temporarily clears the planet');
advance($battle, 2.6);
$counts = $battle->entity_counts;
ok(($counts->{federation_beam} || 0) + ($counts->{klingon_weapon} || 0) > 0,
    'battle produces faction-specific weapons');
advance($battle, 2.0);
$counts = $battle->entity_counts;
is(($counts->{battle_galaxy_class} || 0) + ($counts->{battle_brel_class} || 0), 1,
    'battle randomly destroys exactly one combatant');
ok($counts->{ship_explosion}, 'losing ship explodes');
is($counts->{debris}, 7, 'ship explosion emits seven debris entities');

for my $seed (1 .. 20) {
    my $random_battle = Asciitrek::Engine->new(columns => 100, rows => 30, seed => $seed,
        event => 'battle');
    my @combatants = grep { /^battle_/ } keys %{$random_battle->entity_counts};
    is(scalar(@combatants), 2, "random battle $seed uses two different factions");
}

my $small = Asciitrek::Engine->new(columns => 60, rows => 20, seed => 2, event => 'battle');
ok($small->entity_counts->{enterprise}, 'undersized battle falls back to Enterprise flyby');
$small->resize(75, 25);
is(length($small->frame_bytes), 75 * 25 * 2, 'resize rebuilds scene for new surface grid');

done_testing;

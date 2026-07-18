package Asciitrek::Engine;

use strict;
use warnings;

our $VERSION = '1.0.0';

use constant {
    COLOR_NONE    => 0,
    COLOR_WHITE   => 1,
    COLOR_CYAN    => 2,
    COLOR_GREEN   => 3,
    COLOR_BLUE    => 4,
    COLOR_MAGENTA => 5,
    COLOR_YELLOW  => 6,
    COLOR_RED     => 7,
};

my %COLOR = (
    WHITE => COLOR_WHITE, CYAN => COLOR_CYAN, GREEN => COLOR_GREEN,
    BLUE => COLOR_BLUE, MAGENTA => COLOR_MAGENTA, YELLOW => COLOR_YELLOW,
    RED => COLOR_RED,
);

my %DEPTH = (
    gui => 1, raider => 2, ship_start => 3, ship_end => 20,
    landmark => 22, background => 30,
);

my $MOTION_SCALE = 1.20;
my $BACKGROUND_SPEED = -(.22 * $MOTION_SCALE * .20);

sub new {
    my ($class, %args) = @_;
    my $self = bless {
        width => _positive_int($args{columns}, 80),
        height => _positive_int($args{rows}, 40),
        now => 0,
        seed => defined($args{seed}) ? int($args{seed}) : time,
        requested_event => $args{event} || 'enterprise',
        requested_direction => $args{direction} || '',
        requested_battle => $args{battle} || '',
        entities => [],
        battles => [],
        next_id => 1,
    }, $class;
    srand($self->{seed});
    $self->_reset_scene;
    return $self;
}

sub _positive_int {
    my ($value, $fallback) = @_;
    return $fallback unless defined($value) && $value =~ /^\d+$/ && $value > 0;
    return int($value);
}

sub resize {
    my ($self, $columns, $rows) = @_;
    $columns = _positive_int($columns, $self->{width});
    $rows = _positive_int($rows, $self->{height});
    return if $columns == $self->{width} && $rows == $self->{height};
    $self->{width} = $columns;
    $self->{height} = $rows;
    $self->_reset_scene;
}

sub dimensions { return ($_[0]{width}, $_[0]{height}); }

sub tick_frame {
    my ($self, $elapsed) = @_;
    $self->tick($elapsed);
    return $self->frame_bytes;
}

sub tick {
    my ($self, $elapsed) = @_;
    $elapsed = 0 unless defined($elapsed) && $elapsed > 0;
    $elapsed = .25 if $elapsed > .25;
    while ($elapsed > 0) {
        my $step = $elapsed > .1 ? .1 : $elapsed;
        $self->_step($step);
        $elapsed -= $step;
    }
}

sub _step {
    my ($self, $seconds) = @_;
    $self->{now} += $seconds;
    my $ticks = $seconds * 10; # Term::Animation originally advanced at 10 Hz.
    $self->_update_battles;

    my @expired;
    for my $entity (@{$self->{entities}}) {
        next if $entity->{dead};
        if ($entity->{trail} && rand() < .01 * $ticks) {
            $self->_add_warp_trail($entity);
        }
        $entity->{frame} += ($entity->{frame_rate} || 0) * $ticks;
        $entity->{x} += ($entity->{vx} || 0) * $ticks;
        $entity->{y} += ($entity->{vy} || 0) * $ticks;

        if ($entity->{wrap}) {
            $entity->{x} += $self->{width} while $entity->{x} < 0;
            $entity->{x} -= $self->{width} while $entity->{x} >= $self->{width};
        }
        if ($entity->{scroll_wrap} && $entity->{x} + $entity->{width} < 0) {
            $entity->{x} = $self->{width} + int(rand($self->{width} / 3 + 1));
            if ($entity->{type} eq 'nebula') {
                my $space = $self->{height} - $entity->{height};
                $entity->{y} = $space > 0 ? int(rand($space + 1)) : 0;
            } elsif ($entity->{type} eq 'planet') {
                $entity->{y} = $self->{height} - $entity->{height};
                $entity->{y} = 0 if $entity->{y} < 0;
            }
        }

        my $offscreen = $entity->{die_offscreen} && (
            $entity->{x} >= $self->{width}
            || $entity->{x} + $entity->{width} < 0
            || $entity->{y} >= $self->{height}
            || $entity->{y} + $entity->{height} < 0
        );
        if ($offscreen || (defined($entity->{expires}) && $self->{now} >= $entity->{expires})) {
            $entity->{dead} = 1;
            push @expired, $entity;
        }
    }

    $self->{entities} = [grep { !$_->{dead} } @{$self->{entities}}];
    for my $entity (@expired) {
        $entity->{on_death}->($self, $entity) if $entity->{on_death};
    }
    $self->{battles} = [grep { !$_->{finished} } @{$self->{battles}}];
}

sub frame_bytes {
    my ($self) = @_;
    my $cells = $self->{width} * $self->{height};
    my @glyph = (32) x $cells;
    my @color = (COLOR_NONE) x $cells;

    my @ordered = sort {
        $b->{z} <=> $a->{z} || $a->{id} <=> $b->{id}
    } grep { !$_->{dead} && !$_->{invisible} } @{$self->{entities}};

    for my $entity (@ordered) {
        my $frames = $entity->{frames};
        my $index = int($entity->{frame} || 0) % @{$frames};
        my $lines = $frames->[$index];
        my $base_x = int($entity->{x});
        my $base_y = int($entity->{y});
        for my $row (0 .. $#{$lines}) {
            my $y = $base_y + $row;
            next if $y < 0 || $y >= $self->{height};
            my @characters = split //, $lines->[$row];
            for my $column (0 .. $#characters) {
                my $x = $base_x + $column;
                next if $x < 0 || $x >= $self->{width};
                my $character = $characters[$column];
                next if $character eq ' ' || $character eq '?';
                my $offset = $y * $self->{width} + $x;
                $glyph[$offset] = ord($character) & 0xff;
                $color[$offset] = $entity->{color};
            }
        }
    }

    my $bytes = '';
    for my $index (0 .. $cells - 1) {
        $bytes .= pack('CC', $glyph[$index], $color[$index]);
    }
    return $bytes;
}

sub debug_entities {
    my ($self) = @_;
    my @debug;
    for my $entity (@{$self->{entities}}) {
        my %copy;
        $copy{$_} = $entity->{$_}
            for qw(id type x y z vx vy width height color frame frame_rate);
        push @debug, \%copy;
    }
    return \@debug;
}

sub entity_counts {
    my ($self) = @_;
    my %count;
    $count{$_->{type}}++ for @{$self->{entities}};
    return \%count;
}

sub _reset_scene {
    my ($self) = @_;
    $self->{entities} = [];
    $self->{battles} = [];
    $self->{now} = 0;
    $self->_add_starfield;
    $self->_add_planet;
    $self->_add_nebula;
    $self->_add_generic_starship(1) if $self->{width} >= 110 && $self->{height} >= 30;
    $self->_add_event($self->{requested_event}, 1);
    $self->{requested_event} = '';
}

sub _entity {
    my ($self, %args) = @_;
    my $shapes = ref($args{shape}) eq 'ARRAY' ? $args{shape} : [$args{shape}];
    my (@frames, $width, $height);
    for my $shape (@{$shapes}) {
        $shape = '' unless defined $shape;
        $shape =~ s/^\n//;
        my @lines = split /\n/, $shape, -1;
        pop @lines if @lines > 1 && $lines[-1] eq '';
        $height = @lines if @lines > ($height || 0);
        for my $line (@lines) {
            $width = length($line) if length($line) > ($width || 0);
        }
        push @frames, \@lines;
    }
    my $entity = {
        id => $self->{next_id}++, type => $args{type} || 'entity',
        frames => \@frames, width => $width || 1, height => $height || 1,
        x => $args{x} || 0, y => $args{y} || 0, z => defined($args{z}) ? $args{z} : 1,
        vx => $args{vx} || 0, vy => $args{vy} || 0,
        frame => $args{frame} || 0, frame_rate => $args{frame_rate} || 0,
        color => $COLOR{$args{color} || 'WHITE'} || COLOR_WHITE,
        wrap => $args{wrap}, scroll_wrap => $args{scroll_wrap},
        die_offscreen => $args{die_offscreen}, expires => $args{expires},
        on_death => $args{on_death}, trail => $args{trail}, data => $args{data},
        invisible => $args{invisible},
    };
    push @{$self->{entities}}, $entity;
    return $entity;
}

sub _paced { return $_[1] * $MOTION_SCALE; }
sub _duration { return $_[1] / $MOTION_SCALE; }

sub _add_starfield {
    my ($self) = @_;
    my @layers = (
        ['MAGENTA', $BACKGROUND_SPEED,       $DEPTH{background} - 6, ['.', '*', '+', '*'], .10, .12],
        ['BLUE',    $BACKGROUND_SPEED * .80, $DEPTH{background} - 4, ['.', '*', '.', '+'], .075, .11],
        ['WHITE',   $BACKGROUND_SPEED * .64, $DEPTH{background} - 2, ['.', '*', '.', '.'], .05, .09],
        ['YELLOW',  $BACKGROUND_SPEED * .512,$DEPTH{background},     ['.', '.', '*', '.'], .035, .07],
    );
    my $total = int(($self->{width} * $self->{height}) / 160 + .5);
    $total = 4 if $total < 4;
    my $per = int($total / @layers);
    my $remainder = $total % @layers;
    for my $layer_index (0 .. $#layers) {
        my ($color, $speed, $z, $frames, $minimum, $span) = @{$layers[$layer_index]};
        my $count = $per + ($layer_index < $remainder ? 1 : 0);
        for (1 .. $count) {
            $self->_entity(type => "star_layer_$layer_index", shape => $frames,
                x => int(rand($self->{width})), y => int(rand($self->{height})), z => $z,
                vx => $speed, frame => int(rand(@{$frames})),
                frame_rate => $self->_paced($minimum + rand($span)), color => $color, wrap => 1);
        }
    }
}

sub _add_planet {
    my ($self) = @_;
    return if grep { $_->{type} eq 'planet' && !$_->{dead} } @{$self->{entities}};
    my $shape = q{
       _.-._
    .-'     `-.
   /  .-.      \
  |  (   )      |
   \  `-'     /
    `-.___.-'
};
    my $planet = $self->_entity(type => 'planet', shape => $shape,
        x => $self->{width} - 17, y => 0, z => $DEPTH{landmark},
        vx => $BACKGROUND_SPEED, color => 'MAGENTA', scroll_wrap => 1);
    $planet->{y} = $self->{height} - $planet->{height};
    $planet->{y} = 0 if $planet->{y} < 0;
}

sub _add_nebula {
    my ($self) = @_;
    return if $self->{width} < 110;
    my $cloud = q{ .  .:.....:.  .
   .:.....:.
 .   `...'   .  };
    $self->_entity(type => 'nebula', shape => $cloud,
        x => int(rand($self->{width} - 18)), y => int(rand($self->{height} - 8)),
        z => $DEPTH{background} - 2, vx => $BACKGROUND_SPEED,
        color => 'BLUE', scroll_wrap => 1);
}

sub mirror_ascii {
    my ($self, $shape) = @_;
    my %mirror = ('/' => '\\', '\\' => '/', '(' => ')', ')' => '(', '[' => ']',
        ']' => '[', '{' => '}', '}' => '{', '<' => '>', '>' => '<', "'" => '`', '`' => "'");
    my @lines = split /\n/, $shape, -1;
    my $width = 0;
    for my $line (@lines) {
        $width = length($line) if length($line) > $width;
    }
    return join "\n", map {
        my $line = $_ . (' ' x ($width - length($_)));
        join '', map { $mirror{$_} // $_ } reverse split //, $line;
    } @lines;
}

sub _direction {
    my ($self) = @_;
    return -1 if lc($self->{requested_direction}) eq 'left';
    return 1 if lc($self->{requested_direction}) eq 'right';
    return int(rand(2)) ? 1 : -1;
}

sub enterprise_d_art {
    return q{                                _____
                       __...---'-----`---...__
                  _===============================
 ______________,/'      `---..._______...---'
(____________LL). .    ,--'
 /    /.---'       `. /
'--------_  - - - - _/
          `~~~~~~~~' };
}

sub klingon_brel_art {
    return q{         _  ________
     _,-'|`||||||||_\___       _,-,_
    | /_`-'||||||||'   \-____/_ __o`-,
    |[__<==========|----._______(=====/
     `-\___/`----' | ___\--------\_,-'
                    \(___======][]
                     `--" };
}

sub borg_cube_art {
    my @surface = ('#_|#_|#_|#_|#_|#_', '_|#_|#_|#_|#_|#_|#', '|#_||_|#|_#||_|#_|',
        '#|_|#_||_#|_|#_||_', '_|#_|#_||_|#|_#|_|', '#_||_|#|_#||_|#_|#',
        '|#_|#_||_|#|_#||_|', '_|#_||_|#|_#||_|#_');
    return join "\n", '+' . ('-' x 20) . '+',
        (map { '|' . substr($_ . ('_' x 20), 0, 20) . '|' } @surface),
        '+' . ('-' x 20) . '+';
}

sub _generic_ship_art {
    return (
q{__________________          __
\_________________|)____.---'--`---.____
             ||    \----.________.----/
             ||     / /    `--'
           __||____/ /_
          |___         \
              `--------' },
q{___________________          _-_
\==============_=_/ ____.---'---`---.____
            \_ \    \----._________.----/
              \ \   /  /    `-_-'
          __,--`.`-'..'-_
         /____          ||
              `--.____,-' },
q{                                       _
_______________________   ________.--'-`--._____
|____==================_)  \_'===================`
       _,--___.-|__|-.______|=====/  `---'
       `---------._          ~~~~~|
                   `-._ -  -  - ,'
                       \_____,-' },
q{ ___________________        ____....-----....____
(________________LL_)   ==============================
    ______\   \_______.--'.  `---..._____...---'
    `-------..__            ` ,/
                `-._ -  -  - |
                    `-------' },
enterprise_d_art(),
    );
}

sub _add_generic_starship {
    my ($self, $initial) = @_;
    my @ships = _generic_ship_art();
    my $shape = $ships[int(rand(@ships))];
    my $direction = $self->_direction;
    $shape = $self->mirror_ascii($shape) if $direction < 0;
    my $entity = $self->_entity(type => 'starship', shape => $shape,
        vx => $self->_paced(rand(.5) + .15) * $direction, color => 'WHITE',
        z => int(rand($DEPTH{ship_end} - $DEPTH{ship_start})) + $DEPTH{ship_start},
        die_offscreen => 1, trail => 1,
        on_death => sub { $_[0]->_add_generic_starship(0) });
    my $min_y = 1;
    my $max_y = $self->{height} - $entity->{height} - 12;
    $max_y = $self->{height} - $entity->{height} - 1 if $max_y < $min_y;
    if ($initial) {
        $entity->{y} = int($self->{height} * .65) - int($entity->{height} / 2);
        $entity->{y} = $min_y if $entity->{y} < $min_y;
        $entity->{y} = $max_y if $entity->{y} > $max_y;
        $entity->{x} = $self->{width} > $entity->{width}
            ? int(rand($self->{width} - $entity->{width})) : 0;
    } else {
        $entity->{y} = $max_y > $min_y ? int(rand($max_y - $min_y)) + $min_y : $min_y;
        $entity->{x} = $direction > 0 ? 1 - $entity->{width} : $self->{width} - 1;
    }
}

sub _add_warp_trail {
    my ($self, $ship) = @_;
    my $x = $ship->{x} + ($ship->{vx} > 0 ? -7 : $ship->{width});
    my $y = $ship->{y} + int($ship->{height} / 2);
    $self->_entity(type => 'warp_trail', shape => ['.', '..', '....', '......'],
        x => $x, y => $y, z => $ship->{z} + 1,
        vx => $ship->{vx} > 0 ? $self->_paced(-.6) : $self->_paced(.6),
        frame_rate => $self->_paced(.1), color => 'CYAN', die_offscreen => 1,
        expires => $self->{now} + 1.5);
}

sub _next_event { $_[0]->_add_event('', 0); }

sub _add_event {
    my ($self, $requested, $initial) = @_;
    my @events = qw(enterprise borg klingon romulan comet wormhole battle);
    $requested = $events[int(rand(@events))] unless grep { $_ eq $requested } @events;
    return $self->_add_named_flyby('enterprise', enterprise_d_art(), 'CYAN', .22, $initial)
        if $requested eq 'enterprise';
    return $self->_add_named_flyby('borg_cube', borg_cube_art(), 'GREEN', .22, $initial)
        if $requested eq 'borg';
    return $self->_add_named_flyby('klingon', klingon_brel_art(), 'GREEN', .28, $initial)
        if $requested eq 'klingon';
    return $self->_add_romulan if $requested eq 'romulan';
    return $self->_add_named_flyby('comet', "\n .  .  .  .  .  *>\n   .  .  .  .  .  ",
        'WHITE', 1.0, $initial, 0) if $requested eq 'comet';
    return $self->_add_wormhole if $requested eq 'wormhole';
    return $self->_add_battle;
}

sub _add_named_flyby {
    my ($self, $type, $shape, $color, $speed, $initial, $trail) = @_;
    $trail = 1 unless defined $trail;
    my $direction = $self->_direction;
    $shape = $self->mirror_ascii($shape) if $direction < 0;
    my $entity = $self->_entity(type => $type, shape => $shape,
        vx => $self->_paced($speed) * $direction, z => $DEPTH{raider}, color => $color,
        die_offscreen => 1, trail => $trail,
        on_death => sub { $_[0]->_next_event });
    $entity->{x} = $initial
        ? ($direction > 0 ? 0 : $self->{width} - $entity->{width})
        : ($direction > 0 ? 1 - int($entity->{width} / 2)
                          : $self->{width} - int($entity->{width} / 2));
    my $space = $self->{height} - $entity->{height} - 12;
    $space = $self->{height} - $entity->{height} - 1 if $space < 1;
    $entity->{y} = $initial ? 1 : ($space > 1 ? int(rand($space)) + 1 : 1);
    return $entity;
}

sub _add_romulan {
    my ($self) = @_;
    my @frames = (
q{           _n---n_
      __.-'-_/"\_-`-.__
  .--'___.--|`-'|--.___`--.
 /___.----.__d-b__.----.___\
  `-.___ [__]\V/[__] ___.-'
       `----.\_/.----'       },
q{              _n-----n_
      ___.---'-_ /"\ _-`---.___
  _.--' ___.---.-|   |-.---.___ `--._
 /____.------.__d-----b__.------.____\
 |__|          |=====|          |__|
  `-._`---.__ [__]\V/[__] __.---'_.-'
      `---._____\_/_____.---'       },
q{                 _n-----n_
       ___.-----'-_ /"\ _-`----.___
   _.--' ___.----.-|   |-.----.___ `--._
  /____.--------.__d-----b__.--------.____\
 |  |              |=====|              |  |
 |__|__            |__ __|            __|__|
  \ `._`------------`.`-'------------'_.' /
   `-._`--.___   .nn-\ O /-nn.   ___,--'_.-'
       `-.__ `--/ [_] \V/ [_] \--' __.-'
            `---.______\_/______.---'     },
    );
    push @frames, $frames[1];
    my ($max_width, $max_height) = (0, 0);
    for my $frame (@frames) {
        my @lines = split /\n/, $frame, -1;
        $max_height = @lines if @lines > $max_height;
        for my $line (@lines) {
            $max_width = length($line) if length($line) > $max_width;
        }
    }
    for my $frame (@frames) {
        my @lines = split /\n/, $frame, -1;
        my $top = int(($max_height - @lines) / 2);
        @lines = map { (' ' x int(($max_width - length($_)) / 2)) . $_ } @lines;
        $frame = ("\n" x $top) . join("\n", @lines);
    }
    my $entity = $self->_entity(type => 'romulan', shape => \@frames,
        z => $DEPTH{raider}, color => 'GREEN', frame_rate => $self->_paced(.07),
        expires => $self->{now} + $self->_duration(16),
        on_death => sub { $_[0]->_next_event });
    $entity->{x} = int(($self->{width} - $entity->{width}) / 2);
    $entity->{x} = 0 if $entity->{x} < 0;
    $entity->{y} = 1;
}

sub _add_wormhole {
    my ($self) = @_;
    my @template = ('         .-:.....:-.         ', "      .-'           `-.      ",
        "    .'    .-------.    `.    ", "   /    .'   .-.   `.    \\   ",
        '  ;    /    ( @ )    \\    ;  ', "   \\    `.   `-'   .'    /   ",
        "    `.    `-------'    .'    ", "      `-.           .-'      ",
        "         `-:.....:-'         ");
    my @outer = ([1,14],[2,22],[4,25],[6,22],[7,14],[6,6],[4,4],[2,6]);
    my @inner = ([3,14],[3,18],[4,20],[5,18],[5,14],[5,10],[4,8],[3,10]);
    my @frames;
    for my $step (0 .. 7) {
        my @lines = @template;
        substr($lines[$outer[$step][0]], $outer[$step][1], 1) = 'O';
        my $inside = $inner[($step + 3) % 8];
        substr($lines[$inside->[0]], $inside->[1], 1) = 'o';
        push @frames, join("\n", @lines);
    }
    my $entity = $self->_entity(type => 'wormhole', shape => \@frames,
        z => $DEPTH{raider}, color => 'BLUE', vx => $BACKGROUND_SPEED,
        frame_rate => $self->_paced(.11), expires => $self->{now} + $self->_duration(18),
        on_death => sub { $_[0]->_next_event });
    my $x_space = $self->{width} - 29;
    my $y_space = $self->{height} - 9 - 12;
    $y_space = $self->{height} - 9 if $y_space < 1;
    $entity->{x} = $x_space > 0 ? int(rand($x_space)) : 0;
    $entity->{y} = $y_space > 0 ? int(rand($y_space)) : 0;
}

sub _battle_specs {
    return (
        { faction => 'federation', type => 'galaxy_class', shape => enterprise_d_art(),
          color => 'CYAN', weapon_color => 'YELLOW', weapon_kind => 'beam', beam => '=' },
        { faction => 'klingon', type => 'brel_class', shape => klingon_brel_art(),
          color => 'GREEN', weapon_color => 'GREEN', weapon_kind => 'bolt',
          weapon_frames => ['>>>', '==>', '>>>'] },
        { faction => 'borg', type => 'borg_cube', shape => borg_cube_art(),
          color => 'GREEN', weapon_color => 'GREEN', weapon_kind => 'beam', beam => '#' },
    );
}

sub _add_battle {
    my ($self) = @_;
    return $self->_add_named_flyby('enterprise', enterprise_d_art(), 'CYAN', .22, 0)
        if $self->{width} < 70 || $self->{height} < 22;
    $_->{dead} = 1 for grep { $_->{type} eq 'planet' } @{$self->{entities}};
    $self->{entities} = [grep { !$_->{dead} } @{$self->{entities}}];
    my @available = _battle_specs();
    my ($left_index, $right_index);
    my @requested = split /[,+:]/, lc($self->{requested_battle});
    if (@requested == 2 && $requested[0] ne $requested[1]) {
        my %index = map { $available[$_]{faction} => $_ } 0 .. $#available;
        ($left_index, $right_index) = @index{@requested} if exists($index{$requested[0]})
            && exists($index{$requested[1]});
    }
    if (!defined $left_index) {
        $left_index = int(rand(@available));
        $right_index = int(rand(@available - 1));
        $right_index++ if $right_index >= $left_index;
    }
    my @specs = ($available[$left_index], $available[$right_index]);
    my $state = { started => $self->{now}, next_volley => $self->_duration(2),
        resolved => 0, winner => int(rand(2)), specs => \@specs };
    my $left = $self->_entity(type => 'battle_' . $specs[0]{type}, shape => $specs[0]{shape},
        color => $specs[0]{color}, z => $DEPTH{raider}, vx => $self->_paced(.35));
    my $right = $self->_entity(type => 'battle_' . $specs[1]{type},
        shape => $self->mirror_ascii($specs[1]{shape}), color => $specs[1]{color},
        z => $DEPTH{raider}, vx => $self->_paced(-.35));
    $left->{x} = 1 - int($left->{width} * .25); $left->{y} = 1;
    $right->{x} = $self->{width} - int($right->{width} * .75);
    $right->{y} = $self->{height} - $right->{height} - 1;
    $state->{ships} = [$left, $right];
    push @{$self->{battles}}, $state;
}

sub _update_battles {
    my ($self) = @_;
    for my $state (@{$self->{battles}}) {
        next if $state->{finished};
        my $elapsed = $self->{now} - $state->{started};
        my $approach = $self->_duration(2);
        my $resolve = $self->_duration(5);
        if (!$state->{stopped} && $elapsed >= $approach) {
            $_->{vx} = 0 for @{$state->{ships}};
            $state->{stopped} = 1;
        }
        while (!$state->{resolved} && $elapsed < $resolve
                && $elapsed >= $state->{next_volley}) {
            $state->{next_volley} += $self->_duration(1);
            $self->_add_attack($state->{ships}[0], $state->{ships}[1], $state->{specs}[0]);
            $self->_add_attack($state->{ships}[1], $state->{ships}[0], $state->{specs}[1]);
        }
        if (!$state->{resolved} && $elapsed >= $resolve) {
            $state->{resolved} = 1;
            my $loser = $state->{ships}[1 - $state->{winner}];
            my $winner = $state->{ships}[$state->{winner}];
            $self->_add_explosion($loser);
            $loser->{dead} = 1;
            $winner->{vx} = $state->{winner} == 0 ? $self->_paced(.55) : $self->_paced(-.55);
            $winner->{die_offscreen} = 1;
            $winner->{on_death} = sub { $_[0]->_next_event; $state->{finished} = 1 };
            $self->_entity(type => 'planet_restore_timer', shape => '', invisible => 1,
                expires => $self->{now} + $self->_duration(3),
                on_death => sub { $_[0]->_add_planet });
        }
    }
}

sub _add_attack {
    my ($self, $source, $target, $spec) = @_;
    return if $source->{dead} || $target->{dead};
    my $source_x = $source->{x} + int($source->{width} / 2);
    my $source_y = $source->{y} + int($source->{height} / 2);
    my $target_x = $target->{x} + int($target->{width} / 2);
    my $target_y = $target->{y} + int($target->{height} / 2);
    my $dx = $target_x - $source_x;
    my $dy = $target_y - $source_y;
    my $steps = abs($dx) > abs($dy) ? abs($dx) : abs($dy);
    $steps = int($steps + .5); $steps = 1 if $steps < 1;
    if ($spec->{weapon_kind} eq 'beam') {
        my $min_x = $source_x < $target_x ? $source_x : $target_x;
        my $min_y = $source_y < $target_y ? $source_y : $target_y;
        my $width = int(abs($dx)) + 1; my $height = int(abs($dy)) + 1;
        my @beam = map { ' ' x $width } 1 .. $height;
        for my $step (0 .. $steps) {
            my $x = int($source_x + $dx * $step / $steps + .5) - int($min_x);
            my $y = int($source_y + $dy * $step / $steps + .5) - int($min_y);
            substr($beam[$y], $x, 1) = $spec->{beam};
        }
        $self->_entity(type => $spec->{faction} . '_beam', shape => join("\n", @beam),
            x => $min_x, y => $min_y, z => $DEPTH{gui}, color => $spec->{weapon_color},
            expires => $self->{now} + .6);
        return;
    }
    my @frames = @{$spec->{weapon_frames}};
    @frames = map { $self->mirror_ascii($_) } @frames if $dx < 0;
    my $velocity = $self->_paced(2.5);
    $self->_entity(type => $spec->{faction} . '_weapon', shape => \@frames,
        x => $source_x, y => $source_y, z => $DEPTH{gui}, color => $spec->{weapon_color},
        vx => $dx / $steps * $velocity, vy => $dy / $steps * $velocity,
        frame_rate => $self->_paced(.35), expires => $self->{now} + $self->_duration(4),
        die_offscreen => 1);
}

sub _add_explosion {
    my ($self, $ship) = @_;
    my $center_x = $ship->{x} + int($ship->{width} / 2);
    my $center_y = $ship->{y} + int($ship->{height} / 2);
    my @blast = ('    .    ', "  \\ | /  \n -- * -- \n  / | \\  ",
        " .  *  . \n* \\ | / *\n-- (\@) --\n* / | \\ *\n '  *  ' ",
        "*    .   *\n  .     . \n.   *     \n  *    .  ");
    $self->_entity(type => 'ship_explosion', shape => \@blast,
        x => $center_x - 5, y => $center_y - 2, z => $DEPTH{gui}, color => 'RED',
        frame_rate => $self->_paced(.35), expires => $self->{now} + $self->_duration(3));
    for (1 .. 7) {
        $self->_entity(type => 'debris', shape => ['*', '+', '.'],
            x => $center_x, y => $center_y, z => $DEPTH{gui},
            color => rand() < .5 ? 'YELLOW' : 'RED',
            vx => $self->_paced((rand() - .5) * 1.4),
            vy => $self->_paced((rand() - .5) * .8), frame_rate => $self->_paced(.25),
            expires => $self->{now} + $self->_duration(3), die_offscreen => 1);
    }
}

1;

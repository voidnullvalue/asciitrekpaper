# Fidelity contract

The Android wallpaper treats the Perl engine as the source of truth. Java does
not independently place, animate, recolor, mirror, or resolve any scene object.
Each frame crosses JNI as a fixed-size sequence of two-byte cells:

```text
ASCII glyph byte, palette byte
```

Canvas clears to black and draws only non-space cells. Therefore foreground
whitespace remains transparent and cannot erase stars or scenery.

## Timing correspondence

The original `Term::Animation` loop advances at approximately ten ticks per
second. `Asciitrek::Engine` receives elapsed seconds from Android's monotonic
clock and converts them to equivalent ten-Hz simulation ticks. Large elapsed
intervals are subdivided and capped by the wallpaper host, preventing jumps
after preview transitions or screen wake.

The following constants match Asciitrek:

- Global motion/animation scale: `1.20`
- Nearest background speed: 20% of the accelerated `.22` cruiser speed
- Rear star layers: 80%, 64%, and 51.2% of nearest-layer speed
- Enterprise and Borg cruise: `.22 * 1.20`
- Klingon B'rel cruise: `.28 * 1.20`
- Battle approach, volley cadence, resolution, winner departure, explosion,
  debris, and anomaly lifetimes use the same accelerated values

## Artwork and orientation

Enterprise-D, Klingon B'rel, Borg cube, compact Starfleet profiles, Romulan
D'deridex frames, wormhole, comet, planet, nebula, attacks, and explosion
frames are carried as literal Perl strings derived from Asciitrek.

Horizontal mirroring pads every row to a common width before reversing it and
swaps directional glyphs. The D'deridex remains a centered front profile and
animates approach/recede rather than flying sideways.

## Automated guarantees

`t/engine.t` currently verifies:

- frame dimensions and resize reconstruction
- presence, direction, speed, color depth, and twinkle animation of all four
  star layers
- exact 20% parallax cascade
- accelerated Enterprise speed
- lossless padded-art mirror round trip
- every named event and complete frame output
- corrected `22 x 10` Borg terminal geometry
- stationary animated Romulan profile
- drifting and rotating wormhole
- forced Federation/Klingon battle composition
- temporary planet removal
- weapon generation, exactly one destroyed combatant, explosion, and seven
  debris entities
- twenty random battles all contain two distinct factions
- small-grid battle fallback

The test uses deterministic seeds so regressions are reproducible.

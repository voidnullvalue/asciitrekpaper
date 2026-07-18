# Asciitrekpaper

Asciitrekpaper is an Android live wallpaper powered by an embedded Perl
interpreter. It preserves the behavior and exact ASCII assets of
[Asciitrek](https://github.com/voidnullvalue/asciitrek), while replacing its
terminal-only Curses renderer with an Android `WallpaperService` and Canvas.

The project does **not** screen-scrape a terminal or approximate the simulation
in Java. Perl owns the scene, random events, movement, animation, battle rules,
and final glyph/color grid. Android owns lifecycle, timing, DPI adaptation,
preferences, and drawing that grid onto the wallpaper surface.

## Behavior retained

- Enterprise, Borg cube, Klingon B'rel, animated Romulan D'deridex approach,
  comet, rotating wormhole, and mixed-faction battles
- Bidirectional profile art with width-safe mirroring
- Federation, Klingon, and Borg encounters with no same-faction battles
- Random winner, ship explosion, and debris
- Faction-appropriate weapon colors and beam/bolt behavior
- Four right-to-left parallax star layers, 20% depth speed cascade, Doppler
  palette, and independent variable-speed twinkling
- Planet and nebula drift at background speed
- 1.2x motion/animation pace and fully transparent foreground cells
- The five archived compact Starfleet profile variants on sufficiently large
  grids

See [FIDELITY.md](FIDELITY.md) for the behavioral correspondence and tests.

## Android behavior

- `minSdk 23`, `targetSdk 36`
- 20 FPS while visible; no rendering callbacks while hidden
- Adaptive terminal grid calculated from the actual wallpaper surface and
  density-independent glyph size
- Rebuilds the scene on rotation, fold/unfold, preview resize, or glyph-size
  changes
- Framework Java and Canvas only; no Compose, WebView, AppCompat, terminal
  emulator, network permission, or foreground service
- `arm64-v8a` device and `x86_64` emulator builds
- NDK r28 native binaries for 16 KB page-size compatibility

## Prerequisites

- JDK 17
- Android SDK platform 36 and build-tools 36.0.0
- Android NDK `28.2.13676358`
- CMake 3.22.1
- Gradle 8.11.1
- Host Perl, make, curl, tar, and a C toolchain

Set `ANDROID_HOME` and `ANDROID_NDK_HOME`, then build:

```sh
prove -v t/engine.t
./native/build_perl_android.sh
gradle --no-daemon :app:assembleDebug
```

The APK will be at:

```text
app/build/outputs/apk/debug/app-debug.apk
```

Install and open the configuration activity:

```sh
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell am start -n \
  com.voidnullvalue.asciitrekpaper/.MainActivity
```

Use the activity's button to open Android's live-wallpaper preview and picker.

## Desktop engine preview

The bundled headless engine can be inspected without Android:

```sh
perl tools/preview.pl
ASCIITREK_SHIP=battle ASCIITREK_BATTLE=federation,borg perl tools/preview.pl
ASCIITREK_SHIP=klingon ASCIITREK_DIRECTION=left perl tools/preview.pl
```

Press `Ctrl-C` to exit.

## CI and tagged builds

`.github/workflows/android.yml` runs the Perl fidelity suite and builds a debug
APK on every push to `master`, every `v*` tag, and manual dispatch. APKs are
uploaded as workflow artifacts. A `v*` tag also creates or updates the matching
GitHub release and attaches its debug APK.

## License

Asciitrekpaper is a derivative of Asciitrek and ASCIIQuarium and retains the
same GNU General Public License terms: version 2 or, at your option, any later
version (`GPL-2.0-or-later`). See [LICENSE](LICENSE).

This is an unofficial fan project. Star Trek names and designs belong to their
respective rights holders.

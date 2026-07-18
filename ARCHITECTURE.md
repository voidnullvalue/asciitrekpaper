# Architecture

## Rendering pipeline

```text
WallpaperService.Engine
  -> dedicated HandlerThread at 20 FPS
  -> JNI tick(elapsedSeconds)
  -> one embedded Perl interpreter per wallpaper Engine
  -> Asciitrek::Engine composites glyph/color cells
  -> one byte array crosses JNI
  -> Canvas draws non-space monospace glyphs
```

Android can create active and preview wallpaper engines simultaneously. Each
uses an independent Perl interpreter and scene. Perl is built with threads and
multiplicity support, and each interpreter is created, called, and destroyed
on its owning render thread.

## Adaptive grid

`AsciiCanvasRenderer` measures `M` with `Typeface.MONOSPACE` at the selected
density-independent glyph size. Surface width and height divided by measured
cell dimensions produce the Perl column and row count. This uses the dimensions
from `onSurfaceChanged`, avoiding device-model, resolution, aspect-ratio, and
deprecated display API assumptions.

## Embedded Perl

`native/build_perl_android.sh` overlays perl-cross on Perl 5.40.2 and builds a
position-independent static `libperl.a` for every configured ABI. CMake links
that archive into the app's JNI library. The build also bundles only the pure
core pragmas needed to load `Asciitrek::Engine`; no Curses or CPAN runtime is
shipped.

Perl assets are copied from the APK to `noBackupFilesDir`, since Perl module
loading requires filesystem paths. No executable code is downloaded at
runtime.

## Lifecycle and power

Rendering begins only when both the wallpaper is visible and its Surface is
valid. All scheduled frames stop on invisibility or Surface destruction.
Elapsed time resets on resume, and simulation deltas are capped. Native state
is destroyed before the render thread exits.

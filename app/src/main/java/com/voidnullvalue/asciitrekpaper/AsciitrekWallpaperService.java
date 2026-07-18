package com.voidnullvalue.asciitrekpaper;

import android.content.SharedPreferences;
import android.graphics.Canvas;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.SystemClock;
import android.service.wallpaper.WallpaperService;
import android.view.SurfaceHolder;

import java.io.IOException;

public final class AsciitrekWallpaperService extends WallpaperService {
    static final String PREFERENCES = "wallpaper";
    static final String GLYPH_SIZE_DP = "glyph_size_dp";
    static final int DEFAULT_GLYPH_SIZE_DP = 8;

    @Override
    public Engine onCreateEngine() {
        return new TrekEngine();
    }

    private final class TrekEngine extends Engine {
        private static final long FRAME_DELAY_MS = 50L;

        private final HandlerThread renderThread = new HandlerThread("AsciitrekRenderer");
        private final AsciiCanvasRenderer renderer = new AsciiCanvasRenderer();
        private final SharedPreferences preferences = getSharedPreferences(PREFERENCES, MODE_PRIVATE);
        private Handler renderHandler;
        private volatile boolean visible;
        private volatile boolean surfaceReady;
        private volatile boolean destroyed;
        private int surfaceWidth;
        private int surfaceHeight;
        private int configuredGlyphDp = -1;
        private int columns;
        private int rows;
        private long nativeHandle;
        private long previousFrameNanos;
        private String perlRoot;

        private final Runnable renderFrame = new Runnable() {
            @Override
            public void run() {
                if (destroyed || !visible || !surfaceReady) return;
                long started = SystemClock.elapsedRealtimeNanos();
                try {
                    ensureModel();
                    double elapsed = previousFrameNanos == 0L
                            ? 0.05
                            : Math.min(0.25, (started - previousFrameNanos) / 1_000_000_000.0);
                    previousFrameNanos = started;
                    byte[] frame = NativeAsciitrek.tick(nativeHandle, elapsed);
                    Canvas canvas = null;
                    try {
                        canvas = getSurfaceHolder().lockCanvas();
                        if (canvas != null) renderer.draw(canvas, frame);
                    } finally {
                        if (canvas != null) getSurfaceHolder().unlockCanvasAndPost(canvas);
                    }
                } catch (Throwable error) {
                    android.util.Log.e("Asciitrekpaper", "Wallpaper frame failed", error);
                }

                long spentMs = (SystemClock.elapsedRealtimeNanos() - started) / 1_000_000L;
                if (!destroyed && visible && surfaceReady) {
                    renderHandler.postDelayed(this, Math.max(1L, FRAME_DELAY_MS - spentMs));
                }
            }
        };

        TrekEngine() {
            renderThread.start();
            renderHandler = new Handler(renderThread.getLooper());
            try {
                perlRoot = PerlAssets.install(AsciitrekWallpaperService.this);
            } catch (IOException error) {
                throw new IllegalStateException("Could not install bundled Perl scene", error);
            }
        }

        @Override
        public void onVisibilityChanged(boolean isVisible) {
            visible = isVisible;
            previousFrameNanos = 0L;
            renderHandler.removeCallbacks(renderFrame);
            if (isVisible && surfaceReady) renderHandler.post(renderFrame);
        }

        @Override
        public void onSurfaceChanged(SurfaceHolder holder, int format, int width, int height) {
            surfaceWidth = width;
            surfaceHeight = height;
            surfaceReady = width > 0 && height > 0;
            configuredGlyphDp = -1;
            previousFrameNanos = 0L;
            renderHandler.removeCallbacks(renderFrame);
            if (visible && surfaceReady) renderHandler.post(renderFrame);
        }

        @Override
        public void onSurfaceDestroyed(SurfaceHolder holder) {
            surfaceReady = false;
            renderHandler.removeCallbacks(renderFrame);
            super.onSurfaceDestroyed(holder);
        }

        @Override
        public void onDestroy() {
            destroyed = true;
            visible = false;
            renderHandler.removeCallbacksAndMessages(null);
            final long handle = nativeHandle;
            nativeHandle = 0L;
            if (handle != 0L) {
                renderHandler.post(() -> NativeAsciitrek.destroy(handle));
            }
            renderHandler.post(renderThread::quitSafely);
            super.onDestroy();
        }

        private void ensureModel() {
            int glyphDp = preferences.getInt(GLYPH_SIZE_DP, DEFAULT_GLYPH_SIZE_DP);
            glyphDp = Math.max(5, Math.min(16, glyphDp));
            if (nativeHandle != 0L && glyphDp == configuredGlyphDp) return;

            float glyphPx = glyphDp * getResources().getDisplayMetrics().density;
            AsciiCanvasRenderer.Grid grid = renderer.configure(surfaceWidth, surfaceHeight, glyphPx);
            columns = grid.columns;
            rows = grid.rows;
            configuredGlyphDp = glyphDp;
            if (nativeHandle == 0L) {
                nativeHandle = NativeAsciitrek.create(perlRoot, columns, rows,
                        SystemClock.elapsedRealtimeNanos());
                if (nativeHandle == 0L) throw new IllegalStateException("Embedded Perl failed to start");
            } else {
                NativeAsciitrek.resize(nativeHandle, columns, rows);
            }
        }
    }
}

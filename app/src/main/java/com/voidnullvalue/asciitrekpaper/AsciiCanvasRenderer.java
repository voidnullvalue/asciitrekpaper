package com.voidnullvalue.asciitrekpaper;

import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Typeface;

final class AsciiCanvasRenderer {
    static final class Grid {
        final int columns;
        final int rows;

        Grid(int columns, int rows) {
            this.columns = columns;
            this.rows = rows;
        }
    }

    private static final int[] COLORS = {
            Color.TRANSPARENT,
            Color.WHITE,
            Color.rgb(77, 232, 255),
            Color.rgb(105, 240, 174),
            Color.rgb(68, 138, 255),
            Color.rgb(208, 92, 255),
            Color.rgb(255, 213, 79),
            Color.rgb(255, 82, 82)
    };

    private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG | Paint.SUBPIXEL_TEXT_FLAG);
    private float cellWidth;
    private float cellHeight;
    private float baselineOffset;
    private int columns;
    private int rows;

    AsciiCanvasRenderer() {
        paint.setTypeface(Typeface.MONOSPACE);
        paint.setStyle(Paint.Style.FILL);
    }

    Grid configure(int surfaceWidth, int surfaceHeight, float glyphSizePx) {
        paint.setTextSize(glyphSizePx);
        cellWidth = Math.max(1f, paint.measureText("M"));
        Paint.FontMetrics metrics = paint.getFontMetrics();
        cellHeight = Math.max(1f, metrics.descent - metrics.ascent);
        baselineOffset = -metrics.ascent;
        columns = Math.max(20, (int) Math.ceil(surfaceWidth / cellWidth) + 1);
        rows = Math.max(12, (int) Math.ceil(surfaceHeight / cellHeight) + 1);
        return new Grid(columns, rows);
    }

    void draw(Canvas canvas, byte[] frame) {
        canvas.drawColor(Color.BLACK);
        int expected = columns * rows * 2;
        if (frame == null || frame.length < expected) return;

        char[] glyph = new char[1];
        for (int row = 0; row < rows; row++) {
            float y = row * cellHeight + baselineOffset;
            int rowOffset = row * columns * 2;
            for (int column = 0; column < columns; column++) {
                int offset = rowOffset + column * 2;
                int character = frame[offset] & 0xff;
                int color = frame[offset + 1] & 0xff;
                if (character == 0 || character == ' ' || color == 0) continue;
                glyph[0] = (char) character;
                paint.setColor(color < COLORS.length ? COLORS[color] : Color.WHITE);
                canvas.drawText(glyph, 0, 1, column * cellWidth, y, paint);
            }
        }
    }
}

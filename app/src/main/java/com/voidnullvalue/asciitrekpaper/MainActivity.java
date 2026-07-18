package com.voidnullvalue.asciitrekpaper;

import android.app.Activity;
import android.app.WallpaperManager;
import android.content.ComponentName;
import android.content.Intent;
import android.graphics.Color;
import android.os.Bundle;
import android.view.Gravity;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.SeekBar;
import android.widget.TextView;

public final class MainActivity extends Activity {
    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);

        int padding = Math.round(24 * getResources().getDisplayMetrics().density);
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        layout.setGravity(Gravity.CENTER_HORIZONTAL);
        layout.setPadding(padding, padding, padding, padding);
        layout.setBackgroundColor(Color.BLACK);

        TextView title = text("ASCIITREKPAPER", 24, Color.rgb(77, 232, 255));
        layout.addView(title, matchWrap());

        TextView about = text(getString(R.string.about_text), 15, Color.LTGRAY);
        LinearLayout.LayoutParams aboutParams = matchWrap();
        aboutParams.topMargin = padding;
        layout.addView(about, aboutParams);

        TextView sizeLabel = text("", 16, Color.WHITE);
        LinearLayout.LayoutParams labelParams = matchWrap();
        labelParams.topMargin = padding;
        layout.addView(sizeLabel, labelParams);

        int current = getSharedPreferences(AsciitrekWallpaperService.PREFERENCES, MODE_PRIVATE)
                .getInt(AsciitrekWallpaperService.GLYPH_SIZE_DP,
                        AsciitrekWallpaperService.DEFAULT_GLYPH_SIZE_DP);
        SeekBar size = new SeekBar(this);
        size.setMax(11);
        size.setProgress(Math.max(0, Math.min(11, current - 5)));
        layout.addView(size, matchWrap());
        updateSizeLabel(sizeLabel, size.getProgress() + 5);
        size.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override public void onProgressChanged(SeekBar bar, int progress, boolean fromUser) {
                int value = progress + 5;
                updateSizeLabel(sizeLabel, value);
                if (fromUser) {
                    getSharedPreferences(AsciitrekWallpaperService.PREFERENCES, MODE_PRIVATE)
                            .edit().putInt(AsciitrekWallpaperService.GLYPH_SIZE_DP, value).apply();
                }
            }
            @Override public void onStartTrackingTouch(SeekBar bar) {}
            @Override public void onStopTrackingTouch(SeekBar bar) {}
        });

        Button setWallpaper = new Button(this);
        setWallpaper.setText(R.string.set_wallpaper);
        LinearLayout.LayoutParams buttonParams = matchWrap();
        buttonParams.topMargin = padding;
        layout.addView(setWallpaper, buttonParams);
        setWallpaper.setOnClickListener(view -> openWallpaperPreview());

        setContentView(layout);
    }

    private TextView text(String value, float sp, int color) {
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextSize(sp);
        view.setTextColor(color);
        view.setGravity(Gravity.CENTER);
        return view;
    }

    private LinearLayout.LayoutParams matchWrap() {
        return new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
    }

    private void updateSizeLabel(TextView label, int value) {
        label.setText(getString(R.string.glyph_size_value, value));
    }

    private void openWallpaperPreview() {
        ComponentName component = new ComponentName(this, AsciitrekWallpaperService.class);
        Intent direct = new Intent(WallpaperManager.ACTION_CHANGE_LIVE_WALLPAPER)
                .putExtra(WallpaperManager.EXTRA_LIVE_WALLPAPER_COMPONENT, component);
        try {
            startActivity(direct);
        } catch (RuntimeException unavailable) {
            startActivity(new Intent(WallpaperManager.ACTION_LIVE_WALLPAPER_CHOOSER));
        }
    }
}

package com.voidnullvalue.asciitrekpaper;

import android.content.Context;
import android.content.res.AssetManager;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;

final class PerlAssets {
    private static final Object LOCK = new Object();
    private static final String ASSET_ROOT = "perl";
    private static final String VERSION = "1";

    private PerlAssets() {}

    static String install(Context context) throws IOException {
        synchronized (LOCK) {
            File root = new File(context.getNoBackupFilesDir(), "perl-runtime");
            File marker = new File(root, ".version");
            if (!marker.isFile() || !VERSION.equals(readMarker(marker))) {
                deleteTree(root);
                if (!root.mkdirs() && !root.isDirectory()) {
                    throw new IOException("Cannot create " + root);
                }
                copyTree(context.getAssets(), ASSET_ROOT, root);
                try (FileOutputStream output = new FileOutputStream(marker)) {
                    output.write(VERSION.getBytes(java.nio.charset.StandardCharsets.US_ASCII));
                }
            }
            return root.getAbsolutePath();
        }
    }

    private static String readMarker(File marker) throws IOException {
        try (InputStream input = new java.io.FileInputStream(marker)) {
            byte[] bytes = new byte[16];
            int count = input.read(bytes);
            return count < 0 ? "" : new String(bytes, 0, count,
                    java.nio.charset.StandardCharsets.US_ASCII);
        }
    }

    private static void copyTree(AssetManager assets, String assetPath, File output)
            throws IOException {
        String[] children = assets.list(assetPath);
        if (children != null && children.length > 0) {
            if (!output.mkdirs() && !output.isDirectory()) {
                throw new IOException("Cannot create " + output);
            }
            for (String child : children) {
                copyTree(assets, assetPath + "/" + child, new File(output, child));
            }
            return;
        }
        File parent = output.getParentFile();
        if (parent != null && !parent.mkdirs() && !parent.isDirectory()) {
            throw new IOException("Cannot create " + parent);
        }
        try (InputStream input = assets.open(assetPath);
             FileOutputStream sink = new FileOutputStream(output)) {
            byte[] buffer = new byte[8192];
            int count;
            while ((count = input.read(buffer)) >= 0) {
                sink.write(buffer, 0, count);
            }
        }
    }

    private static void deleteTree(File file) {
        if (!file.exists()) return;
        File[] children = file.listFiles();
        if (children != null) {
            for (File child : children) deleteTree(child);
        }
        if (!file.delete()) file.deleteOnExit();
    }
}

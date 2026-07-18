package com.voidnullvalue.asciitrekpaper;

final class NativeAsciitrek {
    static {
        System.loadLibrary("asciitrekpaper");
    }

    private NativeAsciitrek() {}

    static native long create(String perlRoot, int columns, int rows, long seed);
    static native void resize(long handle, int columns, int rows);
    static native byte[] tick(long handle, double elapsedSeconds);
    static native void destroy(long handle);
}

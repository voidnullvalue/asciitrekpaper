#include <jni.h>
#include <android/log.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <EXTERN.h>
#include <perl.h>

#define LOG_TAG "Asciitrekpaper"
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

typedef struct {
    PerlInterpreter *perl;
    SV *engine;
} TrekContext;

static pthread_once_t perl_system_once = PTHREAD_ONCE_INIT;

static void initialize_perl_system(void) {
    int argc = 1;
    char program[] = "asciitrekpaper";
    char *argv_storage[] = {program, NULL};
    char **argv = argv_storage;
    char **environment = NULL;
    PERL_SYS_INIT3(&argc, &argv, &environment);
}

static void throw_illegal_state(JNIEnv *env, const char *message) {
    jclass exception = (*env)->FindClass(env, "java/lang/IllegalStateException");
    if (exception != NULL) (*env)->ThrowNew(env, exception, message);
}

static int perl_failed(JNIEnv *env, const char *operation) {
    if (!SvTRUE(ERRSV)) return 0;
    STRLEN length = 0;
    const char *error = SvPV(ERRSV, length);
    char message[1024];
    snprintf(message, sizeof(message), "%s: %.*s", operation,
             (int) (length > 900 ? 900 : length), error);
    LOGE("%s", message);
    sv_setsv(ERRSV, &PL_sv_undef);
    throw_illegal_state(env, message);
    return 1;
}

static TrekContext *context_from(jlong handle) {
    return (TrekContext *) (intptr_t) handle;
}

JNIEXPORT jlong JNICALL
Java_com_voidnullvalue_asciitrekpaper_NativeAsciitrek_create(
        JNIEnv *env, jclass clazz, jstring root_string, jint columns, jint rows, jlong seed) {
    (void) clazz;
    pthread_once(&perl_system_once, initialize_perl_system);
    const char *root = (*env)->GetStringUTFChars(env, root_string, NULL);
    if (root == NULL) return 0;

    TrekContext *context = calloc(1, sizeof(*context));
    if (context == NULL) {
        (*env)->ReleaseStringUTFChars(env, root_string, root);
        throw_illegal_state(env, "Unable to allocate embedded Perl context");
        return 0;
    }

    context->perl = perl_alloc();
    if (context->perl == NULL) {
        free(context);
        (*env)->ReleaseStringUTFChars(env, root_string, root);
        throw_illegal_state(env, "perl_alloc failed");
        return 0;
    }

    PERL_SET_CONTEXT(context->perl);
    perl_construct(context->perl);
    PL_exit_flags |= PERL_EXIT_DESTRUCT_END;

    size_t library_length = strlen(root) + 5;
    char *library_root = malloc(library_length);
    if (library_root == NULL) {
        perl_destruct(context->perl);
        perl_free(context->perl);
        free(context);
        (*env)->ReleaseStringUTFChars(env, root_string, root);
        throw_illegal_state(env, "Unable to allocate Perl library path");
        return 0;
    }
    snprintf(library_root, library_length, "%s/lib", root);
    char *embedding[] = {
            "asciitrekpaper", "-I", (char *) root, "-I", library_root,
            "-MAsciitrek::Engine", "-e", "0", NULL
    };
    int parse_status = perl_parse(context->perl, NULL, 8, embedding, NULL);
    int run_status = parse_status == 0 ? perl_run(context->perl) : parse_status;
    free(library_root);
    (*env)->ReleaseStringUTFChars(env, root_string, root);
    if (run_status != 0 || perl_failed(env, "Loading Asciitrek::Engine failed")) {
        perl_destruct(context->perl);
        perl_free(context->perl);
        free(context);
        return 0;
    }

    dSP;
    ENTER;
    SAVETMPS;
    PUSHMARK(SP);
    XPUSHs(sv_2mortal(newSVpv("Asciitrek::Engine", 0)));
    XPUSHs(sv_2mortal(newSVpv("columns", 0)));
    XPUSHs(sv_2mortal(newSViv(columns)));
    XPUSHs(sv_2mortal(newSVpv("rows", 0)));
    XPUSHs(sv_2mortal(newSViv(rows)));
    XPUSHs(sv_2mortal(newSVpv("seed", 0)));
    XPUSHs(sv_2mortal(newSViv((IV) seed)));
    PUTBACK;
    int count = call_method("new", G_SCALAR | G_EVAL);
    SPAGAIN;
    if (perl_failed(env, "Creating Asciitrek engine failed") || count != 1) {
        PUTBACK;
        FREETMPS;
        LEAVE;
        perl_destruct(context->perl);
        perl_free(context->perl);
        free(context);
        return 0;
    }
    context->engine = newSVsv(POPs);
    PUTBACK;
    FREETMPS;
    LEAVE;
    return (jlong) (intptr_t) context;
}

JNIEXPORT void JNICALL
Java_com_voidnullvalue_asciitrekpaper_NativeAsciitrek_resize(
        JNIEnv *env, jclass clazz, jlong handle, jint columns, jint rows) {
    (void) clazz;
    TrekContext *context = context_from(handle);
    if (context == NULL) return;
    PERL_SET_CONTEXT(context->perl);
    dSP;
    ENTER;
    SAVETMPS;
    PUSHMARK(SP);
    XPUSHs(context->engine);
    XPUSHs(sv_2mortal(newSViv(columns)));
    XPUSHs(sv_2mortal(newSViv(rows)));
    PUTBACK;
    call_method("resize", G_DISCARD | G_EVAL);
    SPAGAIN;
    perl_failed(env, "Resizing Asciitrek engine failed");
    PUTBACK;
    FREETMPS;
    LEAVE;
}

JNIEXPORT jbyteArray JNICALL
Java_com_voidnullvalue_asciitrekpaper_NativeAsciitrek_tick(
        JNIEnv *env, jclass clazz, jlong handle, jdouble elapsed_seconds) {
    (void) clazz;
    TrekContext *context = context_from(handle);
    if (context == NULL) return NULL;
    PERL_SET_CONTEXT(context->perl);
    dSP;
    ENTER;
    SAVETMPS;
    PUSHMARK(SP);
    XPUSHs(context->engine);
    XPUSHs(sv_2mortal(newSVnv(elapsed_seconds)));
    PUTBACK;
    int count = call_method("tick_frame", G_SCALAR | G_EVAL);
    SPAGAIN;
    if (perl_failed(env, "Advancing Asciitrek frame failed") || count != 1) {
        PUTBACK;
        FREETMPS;
        LEAVE;
        return NULL;
    }
    SV *result = POPs;
    STRLEN length = 0;
    const char *bytes = SvPVbyte(result, length);
    jbyteArray output = (*env)->NewByteArray(env, (jsize) length);
    if (output != NULL) {
        (*env)->SetByteArrayRegion(env, output, 0, (jsize) length, (const jbyte *) bytes);
    }
    PUTBACK;
    FREETMPS;
    LEAVE;
    return output;
}

JNIEXPORT void JNICALL
Java_com_voidnullvalue_asciitrekpaper_NativeAsciitrek_destroy(
        JNIEnv *env, jclass clazz, jlong handle) {
    (void) env;
    (void) clazz;
    TrekContext *context = context_from(handle);
    if (context == NULL) return;
    PERL_SET_CONTEXT(context->perl);
    SvREFCNT_dec(context->engine);
    PL_perl_destruct_level = 1;
    perl_destruct(context->perl);
    perl_free(context->perl);
    free(context);
}

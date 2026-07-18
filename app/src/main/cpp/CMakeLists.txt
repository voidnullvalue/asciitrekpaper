cmake_minimum_required(VERSION 3.22.1)
project(asciitrekpaper C)

set(PERL_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../../native/perl/${ANDROID_ABI}")
set(PERL_ARCHIVE "${PERL_ROOT}/lib/libperl.a")
set(PERL_INCLUDE "${PERL_ROOT}/include/perl")

if(NOT EXISTS "${PERL_ARCHIVE}" OR NOT EXISTS "${PERL_INCLUDE}/perl.h")
    message(FATAL_ERROR
        "Embedded Perl for ${ANDROID_ABI} is missing. Run native/build_perl_android.sh first.")
endif()

add_library(embedded_perl STATIC IMPORTED)
set_target_properties(embedded_perl PROPERTIES IMPORTED_LOCATION "${PERL_ARCHIVE}")

add_library(asciitrekpaper SHARED asciitrek_jni.c)
target_include_directories(asciitrekpaper PRIVATE "${PERL_INCLUDE}")
target_compile_definitions(asciitrekpaper PRIVATE
    NO_LOCALE
    PERL_NO_GET_CONTEXT=1)
target_compile_options(asciitrekpaper PRIVATE -Wall -Wextra -fvisibility=hidden)
target_link_libraries(asciitrekpaper PRIVATE embedded_perl log android m dl)

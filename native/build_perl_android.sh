#!/usr/bin/env bash
set -euo pipefail

project_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
downloads="$project_root/native/downloads"
build_root="$project_root/native/build"
output_root="$project_root/native/perl"
asset_lib="$project_root/app/src/main/assets/perl/lib"

perl_version="${PERL_VERSION:-5.40.2}"
perl_cross_version="${PERL_CROSS_VERSION:-1.6.2}"
android_api="${ANDROID_API:-23}"
ndk="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}"

if [[ -z "$ndk" || ! -d "$ndk/toolchains/llvm/prebuilt" ]]; then
    echo "ANDROID_NDK_HOME must point to Android NDK r28 or newer" >&2
    exit 2
fi

host_tag=""
case "$(uname -s)-$(uname -m)" in
    Linux-x86_64) host_tag="linux-x86_64" ;;
    Darwin-x86_64) host_tag="darwin-x86_64" ;;
    Darwin-arm64) host_tag="darwin-x86_64" ;;
    *) echo "Unsupported build host: $(uname -s)-$(uname -m)" >&2; exit 2 ;;
esac
toolchain="$ndk/toolchains/llvm/prebuilt/$host_tag"

mkdir -p "$downloads" "$build_root" "$output_root" "$asset_lib/warnings"
perl_archive="$downloads/perl-$perl_version.tar.gz"
cross_archive="$downloads/perl-cross-$perl_cross_version.tar.gz"

if [[ ! -f "$perl_archive" ]]; then
    curl -fL "https://www.cpan.org/src/5.0/perl-$perl_version.tar.gz" -o "$perl_archive"
fi
if [[ ! -f "$cross_archive" ]]; then
    curl -fL "https://github.com/arsv/perl-cross/releases/download/$perl_cross_version/perl-cross-$perl_cross_version.tar.gz" -o "$cross_archive"
fi

if [[ $# -eq 0 ]]; then
    abis=(arm64-v8a x86_64)
else
    abis=("$@")
fi

built_source=""
for abi in "${abis[@]}"; do
    case "$abi" in
        arm64-v8a)
            target="aarch64-linux-android"
            clang_prefix="aarch64-linux-android"
            ;;
        x86_64)
            target="x86_64-linux-android"
            clang_prefix="x86_64-linux-android"
            ;;
        *) echo "Unsupported ABI: $abi" >&2; exit 2 ;;
    esac

    source_dir="$build_root/perl-$perl_version-$abi"
    stage="$build_root/stage-$abi"
    destination="$output_root/$abi"
    if [[ -f "$destination/lib/libperl.a" && -f "$destination/include/perl/perl.h" ]]; then
        echo "Reusing cached embedded Perl for $abi"
        continue
    fi
    rm -rf "$source_dir" "$stage" "$destination"
    mkdir -p "$source_dir" "$stage" "$destination/lib" "$destination/include/perl"
    tar -xzf "$perl_archive" --strip-components=1 -C "$source_dir"
    tar -xzf "$cross_archive" --strip-components=1 -C "$source_dir"

    cc="$toolchain/bin/${clang_prefix}${android_api}-clang"
    (
        cd "$source_dir"
        ./configure \
            --target="$target" \
            --with-cc="$cc" \
            --with-ranlib="$toolchain/bin/llvm-ranlib" \
            --with-objdump="$toolchain/bin/llvm-objdump" \
            --sysroot="$toolchain/sysroot" \
            --prefix=/usr \
            --with-libs=dl,m \
            -Dusethreads \
            -Dusemultiplicity \
            -Duse64bitint \
            -Uuseshrplib \
            -Dccflags="-fPIC" \
            -Dcccdlflags="-fPIC" \
            -Dlddlflags="-shared" \
            -Dman1dir=none -Dman3dir=none

        make -j"${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)}"
        make DESTDIR="$stage" install
    )

    libperl="$(find "$source_dir" "$stage" -name libperl.a -type f | head -n 1)"
    core_dir="$(find "$source_dir" "$stage" -path '*/CORE/perl.h' -type f -printf '%h\n' | head -n 1)"
    if [[ -z "$libperl" || -z "$core_dir" ]]; then
        echo "Could not locate built libperl.a or CORE headers for $abi" >&2
        exit 1
    fi
    cp "$libperl" "$destination/lib/libperl.a"
    cp "$core_dir"/*.h "$destination/include/perl/"
    built_source="$source_dir"
done

# These pure-core pragmas are required while loading Asciitrek::Engine.
if [[ ! -f "$asset_lib/strict.pm" || ! -f "$asset_lib/warnings.pm" ]]; then
    if [[ -z "$built_source" ]]; then
        echo "Cached Perl core pragmas are missing" >&2
        exit 1
    fi
    cp "$built_source/lib/strict.pm" "$asset_lib/strict.pm"
    cp "$built_source/lib/warnings.pm" "$asset_lib/warnings.pm"
    cp "$built_source/lib/warnings/register.pm" "$asset_lib/warnings/register.pm"
fi

echo "Embedded Perl $perl_version built for: ${abis[*]}"

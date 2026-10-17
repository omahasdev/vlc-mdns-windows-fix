#!/bin/sh
# Fix VLC 3.0 mDNS discovery on Windows: Chromecast (Renderer stuck on
# "Scanning") and Local Network servers.
#
# libmicrodns, which VLC links into libmicrodns_plugin.dll, never sets
# IP_MULTICAST_IF. Windows then sends the mDNS query out of its default
# multicast interface (for example a Hyper-V or WSL vEthernet adapter), so
# the query never gets to the device. This script builds the plugin with
# the patches in patches/ and installs it.
#
# Usage (Git Bash):
#   vlc-mdns-fix.sh prepare [VLC_VERSION]  download toolchain, VLC SDK, sources
#   vlc-mdns-fix.sh build   [VLC_VERSION]  build the DLL if it is missing or old
#   vlc-mdns-fix.sh install [VLC_VERSION]  replace the installed DLL (admin)
#   vlc-mdns-fix.sh restore [VLC_VERSION]  put the original DLL back (admin)
# Without VLC_VERSION, the version of the installed vlc.exe is used.
#
# Environment:
#   VLC_MDNS_FIX_WORK  folder for sources, DLLs and backups
#                      (default: .work in the repository)
#   VLC_MDNS_FIX_SDK   folder for the toolchain and the VLC SDK
#                      (default: VLC_MDNS_FIX_WORK)
#   VLC_DIR            VLC install folder (default: from the registry)
#
# Each download is verified before use:
#   toolchain        pinned SHA-256 (TOOLCHAIN_SHA256)
#   VLC 7z (SDK)     SHA-256 file from the VideoLAN main server
#   libmicrodns      SHA-512 from contrib/src/microdns/SHA512SUMS of the VLC tag
# The VLC module source, rules.mak, SHA512SUMS and the VLC contrib patches come
# from the VLC tag on GitHub over HTTPS.
set -e

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(dirname "$HERE")
WORK=$(cygpath -u "${VLC_MDNS_FIX_WORK:-$REPO/.work}")
SDK_ROOT=$(cygpath -u "${VLC_MDNS_FIX_SDK:-$WORK}")
TOOLCHAIN_TAG=20260922
TOOLCHAIN_NAME=llvm-mingw-$TOOLCHAIN_TAG-msvcrt-x86_64   # msvcrt, the C runtime of VLC
TOOLCHAIN_SHA256=1e936a4a694fc27f9625e3311f5ec5d6d99abfeaa514fd41c52a4f8347145d1a
TOOLCHAIN=$SDK_ROOT/$TOOLCHAIN_NAME
CC=x86_64-w64-mingw32-clang
WIN_TARGET=0x0601   # Windows 7 API level: struct pollfd and inet_ntop exist
WIN_TAR=/c/Windows/System32/tar.exe   # bsdtar: reads .zip, .7z and .tar.xz
VLC_RAW=https://raw.githubusercontent.com/videolan/vlc
VLC_DOWNLOAD=https://download.videolan.org/pub/videolan/vlc   # main server, not a mirror
LIBMICRODNS_RELEASES=https://github.com/videolabs/libmicrodns/releases/download
PLUGIN=libmicrodns_plugin.dll

die() { echo "ERROR: $*" >&2; exit 1; }
say() { echo "== $*"; }

export PATH="$TOOLCHAIN/bin:$PATH"

# ---------------------------------------------------------------- VLC install
vlc_dir() {
    if [ -n "$VLC_DIR" ]; then cygpath -u "$VLC_DIR"; return; fi
    d=$(powershell -NoProfile -Command \
        "(Get-ItemProperty 'HKLM:\SOFTWARE\VideoLAN\VLC' -ErrorAction SilentlyContinue).InstallDir" | tr -d '\r')
    [ -n "$d" ] || d="$PROGRAMFILES\\VideoLAN\\VLC"
    cygpath -u "$d"
}

vlc_version() {
    [ -f "$(vlc_dir)/vlc.exe" ] || die "vlc.exe not found in $(vlc_dir)"
    exe=$(cygpath -w "$(vlc_dir)/vlc.exe")
    powershell -NoProfile -Command "(Get-Item '$exe').VersionInfo.FileVersion" | tr -d '\r'
}

# ---------------------------------------------------------------- helpers
extract() {   # extract ARCHIVE DEST [tar options...]
    archive=$1; dest=$2; shift 2
    [ -x "$WIN_TAR" ] || die "Windows tar.exe not found: $WIN_TAR"
    mkdir -p "$dest"
    "$WIN_TAR" -xf "$(cygpath -w "$archive")" -C "$(cygpath -w "$dest")" "$@"
}

download() {   # download URL FILE (HTTPS only, also for redirects)
    say "download $1"
    curl -fsSL --proto '=https' --proto-redir '=https' --retry 3 -o "$2" "$1" || \
        { rm -f "$2"; die "download failed: $1"; }
}

verify() {   # verify FILE sha256|sha512 EXPECTED_HEX
    expected=$(echo "$3" | tr 'A-F' 'a-f')
    [ -n "$expected" ] || die "no $2 hash for $(basename "$1")"
    actual=$("${2}sum" "$1" | cut -d' ' -f1)
    if [ "$actual" != "$expected" ]; then
        rm -f "$1"
        die "$2 mismatch for $(basename "$1"): got $actual, expected $expected"
    fi
    say "$2 ok: $(basename "$1")"
}

entry_points() {   # the vlc_entry__* ABI names exported by a plugin DLL
    llvm-objdump -p "$1" | grep -o 'vlc_entry[a-z_]*__[0-9a-z_]*' | sort -u
}

repo_patches() {   # patches of this repository for libmicrodns $1, in name order
    ls "$REPO/patches/libmicrodns-$1-"* 2>/dev/null | sort
}

# ---------------------------------------------------------------- inputs
ensure_toolchain() {
    [ -x "$TOOLCHAIN/bin/$CC.exe" ] && return
    zip="$SDK_ROOT/$TOOLCHAIN_NAME.zip"
    mkdir -p "$SDK_ROOT"
    download "https://github.com/mstorsjo/llvm-mingw/releases/download/$TOOLCHAIN_TAG/$TOOLCHAIN_NAME.zip" "$zip"
    verify "$zip" sha256 "$TOOLCHAIN_SHA256"
    extract "$zip" "$SDK_ROOT"
    rm -f "$zip"
    [ -x "$TOOLCHAIN/bin/$CC.exe" ] || die "toolchain not usable: $TOOLCHAIN"
}

ensure_sdk() {   # VLC plugin headers and libvlccore import library
    SDK=$SDK_ROOT/vlc-$VER/sdk
    [ -f "$SDK/lib/libvlccore.lib" ] && return
    name=vlc-$VER-win64.7z
    pkg="$SDK_ROOT/vlc-$VER/$name"
    mkdir -p "$SDK_ROOT/vlc-$VER"
    download "$VLC_DOWNLOAD/$VER/win64/$name.sha256" "$pkg.sha256"
    download "$VLC_DOWNLOAD/$VER/win64/$name" "$pkg"
    verify "$pkg" sha256 "$(grep "$name" "$pkg.sha256" | cut -d' ' -f1)"
    extract "$pkg" "$SDK_ROOT/vlc-$VER" --strip-components=1 "vlc-$VER/sdk/*"
    rm -f "$pkg" "$pkg.sha256"
    [ -f "$SDK/lib/libvlccore.lib" ] || die "no sdk/lib/libvlccore.lib in $name"
}

ensure_vlc_sources() {   # VLC module source and libmicrodns pin of this VLC tag
    VSRC=$WORK/src/vlc-$VER
    mkdir -p "$VSRC"
    for f in modules/services_discovery/microdns.c contrib/src/microdns/rules.mak \
             contrib/src/microdns/SHA512SUMS; do
        [ -f "$VSRC/$(basename "$f")" ] || download "$VLC_RAW/$VER/$f" "$VSRC/$(basename "$f")"
    done
    LIBVER=$(sed -n 's/^LIBMICRODNS_VERSION *:= *//p' "$VSRC/rules.mak" | tr -d '\r')
    [ -n "$LIBVER" ] || die "no LIBMICRODNS_VERSION in rules.mak of VLC $VER"
    VLC_PATCHES=""
    for p in $(sed -n 's/.*\$(APPLY) \$(SRC)\/microdns\/\([^ ]*\).*/\1/p' "$VSRC/rules.mak" | tr -d '\r'); do
        [ -f "$VSRC/$p" ] || download "$VLC_RAW/$VER/contrib/src/microdns/$p" "$VSRC/$p"
        VLC_PATCHES="$VLC_PATCHES $VSRC/$p"
    done
    [ -n "$(repo_patches "$LIBVER")" ] || \
        die "no patch for libmicrodns $LIBVER in patches/ (adapt the 0.2.0 patches)"
}

ensure_sources() {   # verified libmicrodns tarball, unpacked and patched again each time
    ensure_vlc_sources
    tarball=microdns-$LIBVER.tar.xz
    if [ ! -f "$VSRC/$tarball" ]; then
        download "$LIBMICRODNS_RELEASES/$LIBVER/$tarball" "$VSRC/$tarball"
    fi
    verify "$VSRC/$tarball" sha512 "$(grep " $tarball\$" "$VSRC/SHA512SUMS" | tr -d '\r' | cut -d' ' -f1)"
    LIB=$WORK/src/libmicrodns-$VER
    rm -rf "$LIB"
    extract "$VSRC/$tarball" "$LIB" --strip-components=1
    # the patches VLC applies in its contrib build, in rules.mak order, then ours
    for p in $VLC_PATCHES $(repo_patches "$LIBVER"); do
        (cd "$LIB" && git apply "$p") || die "patch does not apply: $p"
        say "applied $(basename "$p")"
    done
}

build_id() {   # hash of everything in this repository that changes the DLL
    ensure_vlc_sources >&2   # its messages must not go into the hash
    { echo "$VER $LIBVER $TOOLCHAIN_TAG $WIN_TARGET"
      cat $(repo_patches "$LIBVER") "$REPO/build/"* "$0"; } | sha256sum | cut -d' ' -f1
}

# ---------------------------------------------------------------- commands
prepare() {
    ensure_toolchain
    ensure_sdk
    ensure_sources
    say "toolchain: $TOOLCHAIN"
    say "VLC SDK:   $SDK"
    say "sources:   $VSRC, $LIB (libmicrodns $LIBVER, patched)"
}

build() {
    OUT=$WORK/out/$VER
    id=$(build_id)
    if [ -f "$OUT/$PLUGIN" ] && [ "$(cat "$OUT/build.id" 2>/dev/null)" = "$id" ]; then
        say "DLL for VLC $VER is up to date: $OUT/$PLUGIN"; return
    fi
    ensure_toolchain
    ensure_sdk
    ensure_sources
    OBJ=$OUT/obj
    rm -rf "$OBJ"
    mkdir -p "$OBJ"

    # __FILE__ in the VLC log macros: no build folder in the DLL, the same DLL from any folder
    maps="-ffile-prefix-map=$(cygpath -m "$VSRC")=vlc-$VER -ffile-prefix-map=$(cygpath -m "$LIB")=microdns-$LIBVER"
    maps="$maps -ffile-prefix-map=$(cygpath -m "$REPO")=repo -ffile-prefix-map=$(cygpath -m "$SDK")=vlc-sdk"
    defs="-DHAVE_CONFIG_H -D_UNICODE=1 -DUNICODE=1 -D_POSIX_C_SOURCE=200809L -D_BSD_SOURCE=1"
    defs="$defs -D_WIN32_WINNT=$WIN_TARGET -DWINVER=$WIN_TARGET"
    incs="-I$REPO/build -I$LIB -I$LIB/include -I$LIB/compat"
    for src in compat/compat.c compat/inet.c compat/poll.c src/mdns.c src/rr.c; do
        $CC -O2 -w $maps -c $defs $incs "$LIB/$src" -o "$OBJ/$(basename "$src" .c).o"
    done
    llvm-ar rcs "$OBJ/libmicrodns.a" "$OBJ"/*.o

    say "build $PLUGIN for VLC $VER (libmicrodns $LIBVER)"
    $CC -O2 -w $maps -shared -o "$OUT/$PLUGIN" "$VSRC/microdns.c" \
        -include "$REPO/build/vlc_module_prelude.h" \
        -D__PLUGIN__ -DMODULE_NAME=microdns -DMODULE_STRING=\"microdns\" \
        -DVLC_MODULE_COPYRIGHT=VLC_COPYRIGHT_VIDEOLAN -DVLC_MODULE_LICENSE=VLC_LICENSE_LGPL_2_1_PLUS \
        -D_FILE_OFFSET_BITS=64 -D_WIN32_WINNT=$WIN_TARGET -DWINVER=$WIN_TARGET \
        -I"$SDK/include" -I"$SDK/include/vlc/plugins" -I"$LIB/include" \
        "$OBJ/libmicrodns.a" "$SDK/lib/libvlccore.lib" -lws2_32 -liphlpapi \
        -Wl,--no-insert-timestamp
    rm -rf "$OBJ"
    echo "$id" > "$OUT/build.id"
    say "exports: $(entry_points "$OUT/$PLUGIN" | tr '\n' ' ')"
    say "sha256:  $(sha256sum "$OUT/$PLUGIN" | cut -d' ' -f1)"
}

require_admin() {
    net session >/dev/null 2>&1 || die "run as administrator"
    if MSYS_NO_PATHCONV=1 tasklist.exe /NH /FI "IMAGENAME eq vlc.exe" | grep -qi vlc.exe; then
        die "close all VLC windows first"
    fi
}

refresh_cache() {
    VLC=$(vlc_dir)
    rm -f "$VLC/plugins/plugins.dat"
    "$VLC/vlc-cache-gen.exe" "$(cygpath -w "$VLC/plugins")" || die "vlc-cache-gen failed"
    say "plugin cache refreshed"
}

install() {
    require_admin
    VLC=$(vlc_dir)
    target="$VLC/plugins/services_discovery/$PLUGIN"
    ours="$WORK/out/$VER/$PLUGIN"
    backup="$WORK/backup/$VER/$PLUGIN"
    [ -f "$ours" ] || die "no DLL for VLC $VER, run the build first"
    [ -f "$target" ] || die "not found: $target"
    # the administrator step downloads nothing
    [ -x "$TOOLCHAIN/bin/llvm-objdump.exe" ] || die "toolchain missing, run the build first"

    if cmp -s "$ours" "$target"; then say "patched DLL is already installed"; return; fi
    [ "$(entry_points "$ours")" = "$(entry_points "$target")" ] || \
        die "plugin ABI differs from the installed VLC, delete $ours and build again"

    if [ ! -f "$backup" ]; then
        mkdir -p "$(dirname "$backup")"
        cp "$target" "$backup"
        say "original saved: $backup"
    fi
    cp "$ours" "$target"
    say "installed: $target"
    say "sha256:    $(sha256sum "$target" | cut -d' ' -f1)"
    refresh_cache
}

restore() {
    require_admin
    VLC=$(vlc_dir)
    backup="$WORK/backup/$VER/$PLUGIN"
    [ -f "$backup" ] || die "no backup for VLC $VER: $backup"
    cp "$backup" "$VLC/plugins/services_discovery/$PLUGIN"
    say "original DLL restored"
    refresh_cache
}

cmd=${1:-build}
VER=${2:-$(vlc_version)}
case "$VER" in
    3.0.*) ;;
    *) die "VLC $VER is not supported: this fix is for VLC 3.0.x" ;;
esac
say "VLC $VER in $(vlc_dir)"

case "$cmd" in
    prepare) prepare ;;
    build) build ;;
    install) install ;;
    restore) restore ;;
    *) die "unknown command: $cmd (prepare, build, install, restore)" ;;
esac

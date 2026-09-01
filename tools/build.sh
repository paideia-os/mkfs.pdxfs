#!/usr/bin/env bash
# Per-repo build script. Runs paideia-as build over every .pdx source,
# then links this repo's own objects (plus any --extra-obj-dir objects)
# into a flat ELF via `ld -T link.ld`, per paideia-os issue #1976/#1977
# (satellite-tool /bin seeding pipeline).
#
# Resolves paideia-as via (in order):
#   1. $PAIDEIA_AS env var
#   2. paideia-os checkout sibling to this repo: ../paideia-os/tools/paideia-as/target/release/paideia-as
#   3. $HOME/Development/PaideiaOS/tools/paideia-as/target/release/paideia-as
#   4. paideia-as on $PATH (must be >= 0.21.0)
#
# Requires paideia-as >= 0.21.0. The 0.9.0 shipped in $PATH by default does not
# accept the syntax used in this repo.
#
# Usage:
#   tools/build.sh [--extra-obj-dir DIR]...
#
# --extra-obj-dir DIR may be repeated. Every *.o file found directly
# inside DIR (e.g. pre-built libpdx-* dependency objects) is linked
# alongside this repo's own src/*.o objects. A DIR that does not exist
# or holds no .o files contributes nothing — it is not an error.
# tests/*.o objects are compiled but never linked into the ELF.

set -euo pipefail
cd "$(dirname "$0")/.."

EXTRA_OBJECTS=()
OWN_OBJECTS=()

while [ "$#" -gt 0 ]; do
    case "$1" in
        --extra-obj-dir)
            [ "$#" -ge 2 ] || { echo "[build] FAIL: --extra-obj-dir requires an argument" >&2; exit 2; }
            extra_dir="$2"
            shift 2
            shopt -s nullglob
            for obj in "$extra_dir"/*.o; do
                [ -f "$obj" ] && EXTRA_OBJECTS+=("$obj")
            done
            shopt -u nullglob
            ;;
        *)
            echo "[build] FAIL: unrecognized argument: $1" >&2
            exit 2
            ;;
    esac
done

MIN_VERSION="0.21.0"

resolve_paideia_as() {
    if [ -n "${PAIDEIA_AS:-}" ] && [ -x "$PAIDEIA_AS" ]; then
        echo "$PAIDEIA_AS"; return
    fi
    for cand in \
        "../paideia-os/tools/paideia-as/target/release/paideia-as" \
        "$HOME/Development/PaideiaOS/tools/paideia-as/target/release/paideia-as"
    do
        if [ -x "$cand" ]; then
            echo "$cand"; return
        fi
    done
    if command -v paideia-as >/dev/null 2>&1; then
        command -v paideia-as; return
    fi
    return 1
}

version_ge() {
    # $1 = have, $2 = want ; returns 0 if have >= want
    printf '%s\n%s\n' "$2" "$1" | sort -V -C
}

PA="$(resolve_paideia_as || true)"
if [ -z "$PA" ]; then
    echo "[build] FAIL: paideia-as not found. Set PAIDEIA_AS or clone paideia-os as a sibling." >&2
    exit 2
fi
VER="$("$PA" --version | awk '{print $2}')"
if ! version_ge "$VER" "$MIN_VERSION"; then
    echo "[build] FAIL: paideia-as $VER is too old, need >= $MIN_VERSION (found $PA)" >&2
    exit 2
fi
echo "[build] paideia-as $VER at $PA"

BUILD_DIR="build-out"
mkdir -p "$BUILD_DIR"

FAIL=0
COUNT=0
for pdx in src/*.pdx; do
    [ -f "$pdx" ] || continue
    COUNT=$((COUNT + 1))
    obj="$BUILD_DIR/$(basename "$pdx" .pdx).o"
    OWN_OBJECTS+=("$obj")
    if ! "$PA" build --emit elf64 "$pdx" -o "$obj" 2>&1; then
        FAIL=$((FAIL + 1))
    fi
done

if [ -d tests ]; then
    for pdx in tests/*.pdx; do
        [ -f "$pdx" ] || continue
        COUNT=$((COUNT + 1))
        obj="$BUILD_DIR/tests-$(basename "$pdx" .pdx).o"
        if ! "$PA" build --emit elf64 "$pdx" -o "$obj" 2>&1; then
            FAIL=$((FAIL + 1))
        fi
    done
fi

echo "[build] $COUNT source(s), $FAIL failure(s)"
[ "$FAIL" -eq 0 ] || exit 1
echo "[build] OK"

if [ "$FAIL" -eq 0 ] && [ "${#OWN_OBJECTS[@]}" -gt 0 ]; then
    echo "[link] ld -T link.ld -> $BUILD_DIR/mkfs.pdxfs.elf"
    ld -nostdlib --warn-common --fatal-warnings \
        -T link.ld \
        -o "$BUILD_DIR/mkfs.pdxfs.elf" \
        "${OWN_OBJECTS[@]}" "${EXTRA_OBJECTS[@]}"
    echo "[link] OK -> $BUILD_DIR/mkfs.pdxfs.elf"

    objcopy -O binary "$BUILD_DIR/mkfs.pdxfs.elf" "$BUILD_DIR/mkfs.pdxfs.bin"
    echo "[link] OK -> $BUILD_DIR/mkfs.pdxfs.bin"
fi

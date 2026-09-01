#!/usr/bin/env bash
# Per-repo build script. Runs paideia-as build over every .pdx source, then
# (R64v2 satellite-linking closure) links build-out/*.o into a standalone
# ELF via build-out/mkfs.pdxfs.elf when at least one --extra-obj-dir is
# given.
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
# Linking (R64v2): this repo has no link-time access to libpdx-volume,
# libpdx-audit, or libpdx-elevate's own .o's -- the caller (paideia-os's
# tools/build.sh, or a developer working on this repo standalone) passes
# each dependency's build-out directory via a repeatable --extra-obj-dir
# flag. Every *.o found in each --extra-obj-dir is added to the ld command
# line alongside this repo's own build-out/*.o (excluding build-out/tests-
# *.o, which are unit-test objects, never part of the linked binary).
#
# With zero --extra-obj-dir flags, linking is skipped entirely and this
# script behaves exactly as before R64v2 (compile-only, build-out/*.o) --
# this repo's own test/CI usage does not pass the flag and does not need
# a linked ELF.
#
# Usage: tools/build.sh [--extra-obj-dir DIR]...

set -euo pipefail
cd "$(dirname "$0")/.."

MIN_VERSION="0.21.0"
TOOL_NAME="mkfs.pdxfs"

EXTRA_OBJ_DIRS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --extra-obj-dir)
            EXTRA_OBJ_DIRS+=("$2")
            shift 2
            ;;
        *)
            echo "[build] FAIL: unrecognized argument: $1" >&2
            exit 2
            ;;
    esac
done

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
OWN_OBJS=()
for pdx in src/*.pdx; do
    [ -f "$pdx" ] || continue
    COUNT=$((COUNT + 1))
    obj="$BUILD_DIR/$(basename "$pdx" .pdx).o"
    if ! "$PA" build --emit elf64 "$pdx" -o "$obj" 2>&1; then
        FAIL=$((FAIL + 1))
    else
        OWN_OBJS+=("$obj")
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

if [ ${#EXTRA_OBJ_DIRS[@]} -eq 0 ]; then
    echo "[build] no --extra-obj-dir given -- skipping link phase (compile-only)"
    exit 0
fi

LINK_OBJS=("${OWN_OBJS[@]}")
for d in "${EXTRA_OBJ_DIRS[@]}"; do
    if [ ! -d "$d" ]; then
        echo "[build] FAIL: --extra-obj-dir $d does not exist" >&2
        exit 2
    fi
    found=0
    for o in "$d"/*.o; do
        [ -f "$o" ] || continue
        LINK_OBJS+=("$o")
        found=1
    done
    if [ "$found" -eq 0 ]; then
        echo "[build] FAIL: --extra-obj-dir $d has no .o files" >&2
        exit 2
    fi
done

ELF="$BUILD_DIR/$TOOL_NAME.elf"
echo "[build] linking $ELF ($(( ${#LINK_OBJS[@]} )) object(s))"
if ! ld -nostdlib -T link.ld -o "$ELF" "${LINK_OBJS[@]}"; then
    echo "[build] FAIL: ld failed for $ELF" >&2
    exit 1
fi
echo "[build] OK -- $ELF"

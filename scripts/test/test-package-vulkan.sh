#!/usr/bin/env bash
# Verify package-vulkan.sh produces a correct llama-cpp-vulkan package, and
# that it refuses a Vulkan archive that is not the CPU archive plus the backend.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

tag=b12359
version=1.0.0
fail=0

assert_contains() {  # assert_contains <label> <haystack> <needle>
    if printf '%s\n' "$2" | grep -qF -- "$3"; then
        printf 'ok    %s\n' "$1"
    else
        printf 'FAIL  %s\n       expected to find: %s\n' "$1" "$3"
        fail=1
    fi
}

# Counts need equality, since a substring test would pass "1" against "10".
assert_equals() {  # assert_equals <label> <actual> <expected>
    if [ "$2" = "$3" ]; then
        printf 'ok    %s\n' "$1"
    else
        printf 'FAIL  %s (expected %s, got %s)\n' "$1" "$3" "$2"
        fail=1
    fi
}

# Build a synthetic upstream tree under <dir>/llama-<tag>, shaped like the real
# archives, with a regular library, its soname symlink, a tool, and the licence.
make_tree() {  # make_tree <dir>
    local top="$1/llama-${tag}"
    mkdir -p "$top"
    printf 'licence' > "$top/LICENSE"
    printf 'tool' > "$top/llama-cli"
    printf 'base library' > "$top/libggml-base.so.1.0.0"
    ln -s libggml-base.so.1.0.0 "$top/libggml-base.so.1"
}

pack() {  # pack <dir> <tarball>
    tar czf "$2" -C "$1" "llama-${tag}"
}

make_tree "$work/cpu"
pack "$work/cpu" "$work/cpu.tar.gz"

make_tree "$work/vk"
printf 'vulkan backend' > "$work/vk/llama-${tag}/libggml-vulkan.so"
pack "$work/vk" "$work/vk.tar.gz"

# Capture stdout. The script's documented contract is that it prints the path it
# wrote, so asserting it here verifies that contract and keeps the stray path
# line out of the test output.
mkdir -p "$work/out"
deb=$("$here/../package-vulkan.sh" "$work/vk.tar.gz" "$work/cpu.tar.gz" "$version" amd64 "$work/out")

assert_equals "prints the path it wrote" "$deb" "$work/out/llama-cpp-vulkan_${version}_amd64.deb"
[ -f "$deb" ] || { echo "FAIL  package-vulkan.sh produced no .deb at $deb"; exit 1; }

control=$(dpkg-deb -f "$deb")
contents=$(dpkg-deb -c "$deb")

assert_contains "package name"   "$control" "Package: llama-cpp-vulkan"
assert_contains "version"        "$control" "Version: ${version}"
assert_contains "architecture"   "$control" "Architecture: amd64"
assert_contains "maintainer"     "$control" \
    "Maintainer: li-ruijie <1547237+li-ruijie@users.noreply.github.com>"
assert_contains "backend lands beside the base payload" \
    "$contents" "./usr/lib/llama.cpp/libggml-vulkan.so"
assert_contains "root ownership" "$contents" "root/root"

# Equality rather than containment, so an accidental extra dependency fails.
assert_equals "Depends pins the base package and the Vulkan loader" \
    "$(dpkg-deb -f "$deb" Depends)" "llama-cpp (= ${version}), libvulkan1"
assert_equals "Recommends a Vulkan driver through the virtual package" \
    "$(dpkg-deb -f "$deb" Recommends)" "vulkan-icd"

assert_equals "ships exactly one regular file" \
    "$(printf '%s\n' "$contents" | grep -c '^-' || true)" "1"
assert_equals "the backend is unchanged" \
    "$(dpkg-deb --fsys-tarfile "$deb" | tar xO ./usr/lib/llama.cpp/libggml-vulkan.so)" \
    "vulkan backend"

mkdir -p "$work/arm"
arm=$("$here/../package-vulkan.sh" "$work/vk.tar.gz" "$work/cpu.tar.gz" "$version" arm64 "$work/arm")
assert_equals "the architecture is threaded through" \
    "$(dpkg-deb -f "$arm" Architecture)" "arm64"

# Each mismatch below must be refused with status 1 and leave no package behind.
refuses() {  # refuses <label> <vulkan-dir>
    local out="$work/refused-$RANDOM" status=0
    mkdir -p "$out"
    pack "$2" "$out/vk.tar.gz"
    "$here/../package-vulkan.sh" "$out/vk.tar.gz" "$work/cpu.tar.gz" "$version" amd64 "$out" \
        >/dev/null 2>&1 || status=$?
    assert_equals "$1" "$status" "1"
    assert_equals "$1, and writes no package" "$(find "$out" -name '*.deb' | wc -l)" "0"
}

cp -a "$work/vk" "$work/extra"
printf 'stray' > "$work/extra/llama-${tag}/libggml-stray.so"
refuses "refuses an archive that adds a second file" "$work/extra"

cp -a "$work/vk" "$work/missing"
rm "$work/missing/llama-${tag}/llama-cli"
refuses "refuses an archive that lacks a CPU file" "$work/missing"

cp -a "$work/vk" "$work/differs"
printf 'rebuilt base library' > "$work/differs/llama-${tag}/libggml-base.so.1.0.0"
refuses "refuses an archive whose shared library differs" "$work/differs"

cp -a "$work/vk" "$work/relinked"
rm "$work/relinked/llama-${tag}/libggml-base.so.1"
ln -s libggml-other.so "$work/relinked/llama-${tag}/libggml-base.so.1"
refuses "refuses an archive whose symlink points elsewhere" "$work/relinked"

cp -a "$work/cpu" "$work/nobackend"
refuses "refuses an archive with no backend" "$work/nobackend"

status=0
"$here/../package-vulkan.sh" "$work/vk.tar.gz" >/dev/null 2>&1 || status=$?
assert_equals "wrong argument count is a usage error" "$status" "2"

exit "$fail"

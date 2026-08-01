#!/usr/bin/env bash
# Verify package-base.sh produces a correct llama-cpp package.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

tag=b10216
version=0.0.10216
fail=0

assert_contains() {  # assert_contains <label> <haystack> <needle>
    if printf '%s\n' "$2" | grep -qF -- "$3"; then
        printf 'ok    %s\n' "$1"
    else
        printf 'FAIL  %s\n       expected to find: %s\n' "$1" "$3"
        fail=1
    fi
}

# Counts need equality, since a substring test would pass "23" against "230".
assert_equals() {  # assert_equals <label> <actual> <expected>
    if [ "$2" = "$3" ]; then
        printf 'ok    %s\n' "$1"
    else
        printf 'FAIL  %s (expected %s, got %s)\n' "$1" "$3" "$2"
        fail=1
    fi
}

curl -fsSL -o "$work/base.tar.gz" \
    "https://github.com/ggml-org/llama.cpp/releases/download/${tag}/llama-${tag}-bin-ubuntu-x64.tar.gz"

# Capture stdout. The script's documented contract is that it prints the path it
# wrote, so asserting it here verifies that contract and keeps the stray path
# line out of the test output.
deb=$("$here/../package-base.sh" "$work/base.tar.gz" "$version" amd64 "$work")

assert_equals "prints the path it wrote" "$deb" "$work/llama-cpp_${version}_amd64.deb"
[ -f "$deb" ] || { echo "FAIL  package-base.sh produced no .deb at $deb"; exit 1; }

control=$(dpkg-deb -f "$deb")
contents=$(dpkg-deb -c "$deb")

assert_contains "package name"        "$control" "Package: llama-cpp"
assert_contains "version"             "$control" "Version: 0.0.10216"
assert_contains "architecture"        "$control" "Architecture: amd64"
assert_contains "maintainer"          "$control" \
    "Maintainer: li-ruijie <1547237+li-ruijie@users.noreply.github.com>"
assert_contains "libgomp1 dependency" "$control" "libgomp1"
assert_contains "libssl alternation"  "$control" "libssl3t64 | libssl3"
assert_contains "debian conflict"     "$control" \
    "Conflicts: llama.cpp-tools, llama.cpp-tools-extra"

assert_contains "payload under /usr/lib" "$contents" "./usr/lib/llama.cpp/llama-cli"
assert_contains "bin symlink"            "$contents" "./usr/bin/llama-cli -> ../lib/llama.cpp/llama-cli"
assert_contains "root ownership"         "$contents" "root/root"
assert_contains "licence installed"      "$contents" "./usr/share/doc/llama-cpp/copyright"

assert_equals "cuda backend absent" \
    "$(printf '%s\n' "$contents" | grep -c 'libggml-cuda' || true)" "0"
assert_equals "licence not left in libdir" \
    "$(printf '%s\n' "$contents" | grep -c 'usr/lib/llama.cpp/LICENSE' || true)" "0"

# The upstream x64 archive carries 23 tools, so 23 symlinks are expected.
# Match the link target, not the path: dpkg-deb -c also lists the ./usr/bin/
# directory itself, which would inflate a plain path match by one. Matching the
# target additionally proves each symlink points into the payload directory.
assert_equals "one symlink per tool" \
    "$(printf '%s\n' "$contents" | grep -c -- '-> ../lib/llama.cpp/' || true)" "23"

# Runtime check. libgomp1 is absent from a clean trixie, so fetch it unprivileged.
dpkg-deb -x "$deb" "$work/root"
( cd "$work" && apt-get download libgomp1 >/dev/null 2>&1 )
dpkg-deb -x "$work"/libgomp1_*.deb "$work/gomp"
gomp="$work/gomp/usr/lib/x86_64-linux-gnu"

direct=$(LD_LIBRARY_PATH="$gomp" "$work/root/usr/lib/llama.cpp/llama-cli" --version 2>&1 || true)
assert_contains "binary runs from its real path" "$direct" "version: 10216"

viasym=$(LD_LIBRARY_PATH="$gomp" "$work/root/usr/bin/llama-cli" --version 2>&1 || true)
assert_contains "binary runs through the symlink" "$viasym" "version: 10216"

devices=$(LD_LIBRARY_PATH="$gomp" "$work/root/usr/bin/llama-cli" --list-devices 2>&1 || true)
assert_contains "device listing works with no CUDA present" "$devices" "Available devices:"

exit "$fail"

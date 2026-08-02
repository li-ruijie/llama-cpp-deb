#!/usr/bin/env bash
# Verify package-cuda.sh produces a correct llama-cpp-cuda package.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

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

# Counts need equality, since a substring test would pass "1" against "10".
assert_equals() {  # assert_equals <label> <actual> <expected>
    if [ "$2" = "$3" ]; then
        printf 'ok    %s\n' "$1"
    else
        printf 'FAIL  %s (expected %s, got %s)\n' "$1" "$3" "$2"
        fail=1
    fi
}

# A stub standing in for the compiled backend.
printf 'not a real library' > "$work/libggml-cuda.so"

# Capture stdout. The script's documented contract is that it prints the path it
# wrote, so asserting it here verifies that contract and keeps the stray path
# line out of the test output.
deb=$("$here/../package-cuda.sh" "$work/libggml-cuda.so" "$version" "$work")

assert_equals "prints the path it wrote" "$deb" "$work/llama-cpp-cuda_${version}_amd64.deb"
[ -f "$deb" ] || { echo "FAIL  package-cuda.sh produced no .deb at $deb"; exit 1; }

control=$(dpkg-deb -f "$deb")
contents=$(dpkg-deb -c "$deb")

assert_contains "package name"   "$control" "Package: llama-cpp-cuda"
assert_contains "version"        "$control" "Version: 0.0.10216"
assert_contains "architecture"   "$control" "Architecture: amd64"
assert_contains "backend lands beside the base payload" \
    "$contents" "./usr/lib/llama.cpp/libggml-cuda.so"
assert_contains "root ownership" "$contents" "root/root"

# The design turns on declaring no CUDA dependency, so guard that explicitly.
# Check the Depends line alone, since the Description legitimately names cuBLAS.
depends=$(printf '%s\n' "$control" | grep '^Depends:' || true)

# Equality, not containment: "and nothing else" is the requirement, so an
# appended non-CUDA dependency must fail even though the keyword scan below
# would not catch it.
assert_equals "Depends is exactly the version-pinned base package" \
    "$depends" "Depends: llama-cpp (= ${version})"

for forbidden in cublas cudart nvidia; do
    assert_equals "Depends names no $forbidden" \
        "$(printf '%s\n' "$depends" | grep -ci "$forbidden" || true)" "0"
done

# It must ship exactly one file, otherwise it is duplicating the base package.
assert_equals "ships exactly one regular file" \
    "$(printf '%s\n' "$contents" | grep -c '^-' || true)" "1"

exit "$fail"

#!/usr/bin/env bash
# Verify package-cuda.sh produces a correct llama-cpp-cuda package.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

version=0.0.10216
cuda_suffix=13-3
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
deb=$("$here/../package-cuda.sh" "$work/libggml-cuda.so" "$version" "$cuda_suffix" "$work")

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

# Check the Depends line alone, since the Description also names these packages
# in prose. Equality rather than containment, so an accidental extra dependency
# fails rather than slipping through.
depends=$(printf '%s\n' "$control" | grep '^Depends:' || true)
assert_equals "Depends pins the base package and the matching CUDA runtime" \
    "$depends" \
    "Depends: llama-cpp (= ${version}), cuda-libraries-${cuda_suffix}"

# The suffix must be threaded through, not hardcoded, or a container bump would
# silently keep depending on the old CUDA release.
mkdir -p "$work/other"
other=$("$here/../package-cuda.sh" "$work/libggml-cuda.so" "$version" 14-1 "$work/other")
assert_contains "the CUDA suffix is threaded through, not hardcoded" \
    "$(dpkg-deb -f "$other" Depends)" "cuda-libraries-14-1"

# The bare "cuda" metapackage depends on nvidia-open, which collides with a
# distribution-packaged driver, so it must never appear.
assert_equals "Depends does not pull the cuda metapackage or a driver" \
    "$(printf '%s\n' "$depends" | grep -cE '(^|, )cuda(,|$)|nvidia-open|nvidia-driver|libcuda1' || true)" "0"

# A malformed suffix must be rejected rather than producing a broken dependency.
status=0
"$here/../package-cuda.sh" "$work/libggml-cuda.so" "$version" "13.3" "$work" >/dev/null 2>&1 \
    || status=$?
assert_equals "a malformed CUDA suffix is rejected" "$status" "2"

# It must ship exactly one file, otherwise it is duplicating the base package.
assert_equals "ships exactly one regular file" \
    "$(printf '%s\n' "$contents" | grep -c '^-' || true)" "1"

exit "$fail"

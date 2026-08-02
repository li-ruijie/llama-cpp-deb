#!/usr/bin/env bash
# Verify smoke-test.sh accepts a sound tree and rejects a broken backend.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

tag=b10216
version=0.0.10216
cuda_suffix=13-3
fail=0

report() {  # report <label> <expected-status> <actual-status>
    if [ "$2" = "$3" ]; then
        printf 'ok    %s\n' "$1"
    else
        printf 'FAIL  %s (expected exit %s, got %s)\n' "$1" "$2" "$3"
        fail=1
    fi
}

contains() {  # contains <label> <haystack> <needle>
    if printf '%s\n' "$2" | grep -qF -- "$3"; then
        printf 'ok    %s\n' "$1"
    else
        printf 'FAIL  %s\n       expected to find: %s\n' "$1" "$3"
        fail=1
    fi
}

curl -fsSL -o "$work/base.tar.gz" \
    "https://github.com/ggml-org/llama.cpp/releases/download/${tag}/llama-${tag}-bin-ubuntu-x64.tar.gz"
base=$("$here/../package-base.sh" "$work/base.tar.gz" "$version" amd64 "$work")

# libgomp1 is absent from a clean trixie, and the smoke test needs it on the path.
( cd "$work" && apt-get download libgomp1 >/dev/null 2>&1 )
dpkg-deb -x "$work"/libgomp1_*.deb "$work/gomp"
export CUDA_STUB_DIR="$work/gomp/usr/lib/x86_64-linux-gnu"

# A backend that is not even an ELF object must be rejected.
printf 'not a real library' > "$work/broken.so"
broken=$("$here/../package-cuda.sh" "$work/broken.so" "$version" "$cuda_suffix" "$work")
status=0
"$here/../smoke-test.sh" "$base" "$broken" >/dev/null 2>&1 || status=$?
report "a corrupt backend is rejected" 1 "$status"

# The base package alone must pass, since there is no backend to resolve.
status=0
"$here/../smoke-test.sh" "$base" >/dev/null 2>&1 || status=$?
report "the base package alone passes" 0 "$status"

# The real ABI guard. A backend can be a perfectly valid ELF and still fail to
# resolve against the base package, which is exactly what a ggml ABI mismatch
# looks like. ldd -r exits 0 in that case, so the greps over its output are the
# only thing standing between a broken build and the APT repository. The corrupt
# stub above never reaches them, since ldd -r exits 1 on a non-ELF file and the
# script bails at the earlier branch.
#
# libggml-cpu-haswell.so out of the base package stands in for such a backend.
# With libgomp off the path it reports both a missing non-CUDA library and
# undefined symbols. Assert on the messages rather than the exit status alone,
# since llama-cli also fails without libgomp, so a bare status check would pass
# for the wrong reason.
dpkg-deb -x "$base" "$work/basetree"
mkdir -p "$work/abi"
cp "$work/basetree/usr/lib/llama.cpp/libggml-cpu-haswell.so" "$work/abi/libggml-cuda.so"
unresolvable=$("$here/../package-cuda.sh" "$work/abi/libggml-cuda.so" "$version" "$cuda_suffix" "$work/abi")

status=0
out=$(CUDA_STUB_DIR= "$here/../smoke-test.sh" "$base" "$unresolvable" 2>&1) || status=$?
report "an unresolvable backend is rejected" 1 "$status"
contains "the missing-library branch fires" "$out" \
    "the backend is missing a non-CUDA library"
contains "the undefined-symbol branch fires" "$out" \
    "the backend has undefined symbols against the base package"

exit "$fail"

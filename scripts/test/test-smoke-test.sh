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
# libggml-cpu-haswell.so out of the base package stands in for such a backend,
# with one name in it renamed per case. Each rename keeps the length, so the ELF
# stays valid. Renaming libgomp.so.1 to libgomx.so.1 gives a library no host
# carries, and renaming the imported ggml_abort to ggml_abxrt gives a symbol the
# base package does not export. They are separate cases, since ldd -r stops at a
# missing library and reports no undefined symbols alongside it. Neither relies
# on what the host has installed. Assert on the messages rather than the exit
# status alone, so a status check cannot pass for the wrong reason.
dpkg-deb -x "$base" "$work/basetree"
haswell="$work/basetree/usr/lib/llama.cpp/libggml-cpu-haswell.so"

broken_cuda() {  # broken_cuda <perl substitution> <dir>, prints the package path
    mkdir -p "$2"
    perl -pe "$1" "$haswell" > "$2/libggml-cuda.so"
    "$here/../package-cuda.sh" "$2/libggml-cuda.so" "$version" "$cuda_suffix" "$2"
}

nolib=$(broken_cuda 's/libgomp\.so\.1/libgomx.so.1/g' "$work/nolib")
status=0
out=$("$here/../smoke-test.sh" "$base" "$nolib" 2>&1) || status=$?
report "a backend missing a library is rejected" 1 "$status"
contains "the missing-library branch fires" "$out" \
    "the backend is missing a non-CUDA library"

nosym=$(broken_cuda 's/ggml_abort/ggml_abxrt/g' "$work/nosym")
status=0
out=$("$here/../smoke-test.sh" "$base" "$nosym" 2>&1) || status=$?
report "a backend with an unresolvable symbol is rejected" 1 "$status"
contains "the undefined-symbol branch fires" "$out" \
    "the backend has undefined symbols against the base package"

exit "$fail"

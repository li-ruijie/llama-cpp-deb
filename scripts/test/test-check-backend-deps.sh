#!/usr/bin/env bash
# Verify check-backend-deps.sh accepts the declared CUDA set and rejects anything else.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fail=0

expect() {  # expect <label> <expected-status> <soname-list>
    status=0
    printf '%s\n' "$3" | "$here/../check-backend-deps.sh" - >/dev/null 2>&1 || status=$?
    if [ "$status" = "$2" ]; then
        printf 'ok    %s\n' "$1"
    else
        printf 'FAIL  %s (expected exit %s, got %s)\n' "$1" "$2" "$status"
        fail=1
    fi
}

# What the backend actually links today, taken from readelf on a published build.
expect "the current linkage is accepted" 0 \
"libggml-base.so.0
libcudart.so.13
libcublas.so.13
libcuda.so.1
libstdc++.so.6
libm.so.6
libgcc_s.so.1
libc.so.6"

expect "libcublasLt is accepted, it ships inside libcublas" 0 \
"libcudart.so.13
libcublas.so.13
libcublasLt.so.13"

# The case this check exists for: a future llama.cpp linking another CUDA library.
expect "cuFFT is rejected" 1 \
"libcudart.so.13
libcublas.so.13
libcufft.so.12"

expect "cuSOLVER is rejected" 1 \
"libcudart.so.13
libcusolver.so.12"

# The one that already happened once, via a build-container leak.
expect "NCCL is rejected" 1 \
"libcudart.so.13
libcublas.so.13
libnccl.so.2"

expect "nvrtc is rejected" 1 \
"libcudart.so.13
libnvrtc.so.13"

# A backend with no CUDA linkage at all is not this check's business.
expect "a CUDA-free object is accepted" 0 \
"libggml-base.so.0
libgomp.so.1
libc.so.6"

# Real ELF, exercising the readelf path rather than the stdin path. The base
# package's CPU backend links no CUDA, so it must pass.
if [ -f /tmp/llamachk/x/libggml-cpu-haswell.so ]; then
    status=0
    "$here/../check-backend-deps.sh" /tmp/llamachk/x/libggml-cpu-haswell.so >/dev/null 2>&1 \
        || status=$?
    if [ "$status" = "0" ]; then
        printf 'ok    %s\n' "reads DT_NEEDED from a real shared object"
    else
        printf 'FAIL  %s (expected exit 0, got %s)\n' "reads DT_NEEDED from a real shared object" "$status"
        fail=1
    fi
else
    printf 'skip  reads DT_NEEDED from a real shared object (no fixture present)\n'
fi

exit "$fail"

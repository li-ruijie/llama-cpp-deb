#!/usr/bin/env bash
# Verify a llama-cpp tree loads, and that any CUDA backend resolves against it.
#
# CUDA_STUB_DIR, when set, is appended to LD_LIBRARY_PATH. On a build runner it
# should point at the CUDA toolkit stub directory, which supplies libcuda.so.1
# in place of a real driver.
set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    echo "usage: $0 <base.deb> [cuda.deb]" >&2
    exit 2
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

for deb in "$@"; do
    dpkg-deb -x "$deb" "$work/root"
done

tree="$work/root/usr/lib/llama.cpp"
export LD_LIBRARY_PATH="$tree${CUDA_STUB_DIR:+:$CUDA_STUB_DIR}"

status=0

if [ -f "$tree/libggml-cuda.so" ]; then
    echo "== resolving libggml-cuda.so against the base package =="
    # ldd -r performs relocation, so it reports undefined symbols rather than
    # only missing libraries. That is the ABI check this whole design rests on.
    if ! unresolved=$(ldd -r "$tree/libggml-cuda.so" 2>&1); then
        echo "ldd could not process the backend at all:" >&2
        printf '%s\n' "$unresolved" >&2
        exit 1
    fi
    printf '%s\n' "$unresolved"

    # Missing CUDA libraries are expected and acceptable. Anything else is not.
    if printf '%s\n' "$unresolved" \
        | grep 'not found' \
        | grep -qvE 'libcuda\.so|libcudart\.so|libcublas\.so|libcublasLt\.so'; then
        echo "the backend is missing a non-CUDA library" >&2
        status=1
    fi

    if printf '%s\n' "$unresolved" | grep -q 'undefined symbol'; then
        echo "the backend has undefined symbols against the base package" >&2
        status=1
    fi
fi

echo "== running llama-cli --list-devices =="
if ! devices=$("$tree/llama-cli" --list-devices 2>&1); then
    echo "llama-cli failed to run:" >&2
    printf '%s\n' "$devices" >&2
    exit 1
fi
printf '%s\n' "$devices"

exit "$status"

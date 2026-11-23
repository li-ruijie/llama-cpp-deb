#!/usr/bin/env bash
# Verify a llama-cpp tree loads, and that any GPU backend resolves against it.
#
# CUDA_STUB_DIR, when set, is appended to LD_LIBRARY_PATH. On a build runner it
# should point at the CUDA toolkit stub directory, which supplies libcuda.so.1
# in place of a real driver.
set -euo pipefail

if [ "$#" -lt 1 ]; then
    echo "usage: $0 <base.deb> [backend.deb...]" >&2
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

# check_backend <name> [tolerated]: resolve one backend against the base package.
# tolerated is an extended regex of libraries allowed to be missing, and when it
# is empty every library must resolve.
check_backend() {
    local name=$1 tolerated=${2:-} unresolved
    echo "== resolving $name against the base package =="
    # ldd -r performs relocation, so it reports undefined symbols rather than
    # only missing libraries. That is the ABI check this whole design rests on.
    if ! unresolved=$(ldd -r "$tree/$name" 2>&1); then
        echo "ldd could not process $name at all:" >&2
        printf '%s\n' "$unresolved" >&2
        exit 1
    fi
    printf '%s\n' "$unresolved"

    if printf '%s\n' "$unresolved" | grep 'not found' \
        | { if [ -n "$tolerated" ]; then grep -vE "$tolerated"; else cat; fi; } \
        | grep -q .; then
        echo "$name is missing a library" >&2
        status=1
    fi

    if printf '%s\n' "$unresolved" | grep -q 'undefined symbol'; then
        echo "$name has undefined symbols against the base package" >&2
        status=1
    fi
}

# Missing CUDA libraries are expected and acceptable, since the build runner has
# no driver. The Vulkan loader is installed wherever this runs, so nothing may be
# missing for that backend.
if [ -f "$tree/libggml-cuda.so" ]; then
    check_backend libggml-cuda.so 'libcuda\.so|libcudart\.so|libcublas\.so|libcublasLt\.so'
fi
if [ -f "$tree/libggml-vulkan.so" ]; then
    check_backend libggml-vulkan.so
fi

echo "== running llama-cli --list-devices =="
if ! devices=$("$tree/llama-cli" --list-devices 2>&1); then
    echo "llama-cli failed to run:" >&2
    printf '%s\n' "$devices" >&2
    exit 1
fi
printf '%s\n' "$devices"

exit "$status"

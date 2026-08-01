#!/usr/bin/env bash
# Verify smoke-test.sh accepts a sound tree and rejects a broken backend.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

tag=b10216
version=0.0.10216
fail=0

report() {  # report <label> <expected-status> <actual-status>
    if [ "$2" = "$3" ]; then
        printf 'ok    %s\n' "$1"
    else
        printf 'FAIL  %s (expected exit %s, got %s)\n' "$1" "$2" "$3"
        fail=1
    fi
}

curl -fsSL -o "$work/base.tar.gz" \
    "https://github.com/ggml-org/llama.cpp/releases/download/${tag}/llama-${tag}-bin-ubuntu-x64.tar.gz"
"$here/../package-base.sh" "$work/base.tar.gz" "$version" amd64 "$work" >/dev/null
base="$work/llama-cpp_${version}_amd64.deb"

# libgomp1 is absent from a clean trixie, and the smoke test needs it on the path.
( cd "$work" && apt-get download libgomp1 >/dev/null 2>&1 )
dpkg-deb -x "$work"/libgomp1_*.deb "$work/gomp"
export CUDA_STUB_DIR="$work/gomp/usr/lib/x86_64-linux-gnu"

# A backend that is not even an ELF object must be rejected.
printf 'not a real library' > "$work/broken.so"
"$here/../package-cuda.sh" "$work/broken.so" "$version" "$work" >/dev/null
status=0
"$here/../smoke-test.sh" "$base" "$work/llama-cpp-cuda_${version}_amd64.deb" >/dev/null 2>&1 \
    || status=$?
report "a corrupt backend is rejected" 1 "$status"

# The base package alone must pass, since there is no backend to resolve.
status=0
"$here/../smoke-test.sh" "$base" >/dev/null 2>&1 || status=$?
report "the base package alone passes" 0 "$status"

exit "$fail"

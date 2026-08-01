#!/usr/bin/env bash
# Assemble llama-cpp-cuda_<version>_amd64.deb from a compiled libggml-cuda.so.
set -euo pipefail

if [ "$#" -ne 3 ]; then
    echo "usage: $0 <libggml-cuda.so> <version> <outdir>" >&2
    exit 2
fi

backend=$1
version=$2
outdir=$3

staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT

root="$staging/root"
mkdir -p "$root/DEBIAN" "$root/usr/lib/llama.cpp"

# dpkg-deb rejects a control directory outside 0755 to 0775.
chmod 0755 "$root/DEBIAN"

install -m 644 "$backend" "$root/usr/lib/llama.cpp/libggml-cuda.so"

cat > "$root/DEBIAN/control" <<EOF
Package: llama-cpp-cuda
Version: ${version}
Architecture: amd64
Maintainer: li-ruijie <1547237+li-ruijie@users.noreply.github.com>
Homepage: https://github.com/ggml-org/llama.cpp
Depends: llama-cpp (= ${version})
Section: misc
Priority: optional
Description: llama.cpp, CUDA backend
 NVIDIA CUDA backend for llama-cpp, compiled for compute capabilities 8.9
 and 12.0 with PTX fallback from 9.0.
 .
 The CUDA runtime is deliberately not bundled, since cuBLAS alone is an
 818 MB archive. This package needs libcudart.so.13 and libcublas.so.13
 from NVIDIA's CUDA repository, plus a 580 series or newer driver. Where
 any of that is missing, ggml skips the backend and llama-cpp runs on CPU.
EOF

deb="$outdir/llama-cpp-cuda_${version}_amd64.deb"
dpkg-deb --root-owner-group --build "$root" "$deb" >/dev/null
echo "$deb"

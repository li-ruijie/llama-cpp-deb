#!/usr/bin/env bash
# Assemble llama-cpp-cuda_<version>_amd64.deb from a compiled libggml-cuda.so.
#
# cuda-suffix is the CUDA release in NVIDIA's apt package-name form, so 13.3
# becomes 13-3. It must match the toolkit the backend was compiled against,
# since the sonames it records are version specific.
set -euo pipefail

if [ "$#" -ne 4 ]; then
    echo "usage: $0 <libggml-cuda.so> <version> <cuda-suffix> <outdir>" >&2
    exit 2
fi

backend=$1
version=$2
cuda_suffix=$3
outdir=$4

case "$cuda_suffix" in
    [0-9]*-[0-9]*) ;;
    *)
        echo "$0: cuda-suffix must look like 13-3, got '$cuda_suffix'" >&2
        exit 2
        ;;
esac

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
Depends: llama-cpp (= ${version}), cuda-cudart-${cuda_suffix}, libcublas-${cuda_suffix}
Section: misc
Priority: optional
Description: llama.cpp, CUDA backend
 NVIDIA CUDA backend for llama-cpp, compiled for compute capabilities 8.9
 and 12.0 with PTX fallback from 9.0.
 .
 The CUDA runtime is depended on rather than bundled, since cuBLAS alone is
 an 818 MB archive. Those packages come from NVIDIA's own CUDA apt
 repository, which must be configured on the target machine. Debian's
 nvidia-cuda-toolkit is 12.4 and is both too old for compute capability 12.0
 and the wrong soname for a CUDA 13 build.
 .
 The NVIDIA driver is deliberately not depended on, since its package name
 varies across distributions. A 580 series or newer driver is required. Where
 the driver is missing, ggml skips the backend and llama-cpp runs on CPU.
EOF

deb="$outdir/llama-cpp-cuda_${version}_amd64.deb"
dpkg-deb --root-owner-group --build "$root" "$deb" >/dev/null
echo "$deb"

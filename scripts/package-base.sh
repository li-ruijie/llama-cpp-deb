#!/usr/bin/env bash
# Assemble llama-cpp_<version>_<arch>.deb from an upstream llama.cpp Ubuntu archive.
set -euo pipefail

if [ "$#" -ne 4 ]; then
    echo "usage: $0 <tarball> <version> <arch> <outdir>" >&2
    exit 2
fi

tarball=$1
version=$2
arch=$3
outdir=$4

staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT

root="$staging/root"
libdir="$root/usr/lib/llama.cpp"
mkdir -p "$root/DEBIAN" "$libdir" "$root/usr/bin"

# dpkg-deb rejects a control directory outside 0755 to 0775, and a restrictive
# umask on the build host would otherwise produce one.
chmod 0755 "$root/DEBIAN"

# The archive holds every file under a single llama-b<N>/ directory.
tar xzf "$tarball" -C "$libdir" --strip-components=1

install -Dm644 "$libdir/LICENSE" "$root/usr/share/doc/llama-cpp/copyright"
rm -f "$libdir/LICENSE"

# Every remaining top-level file that is not a shared object is a tool.
for path in "$libdir"/*; do
    name=$(basename "$path")
    case "$name" in
        *.so | *.so.*) continue ;;
    esac
    chmod 755 "$path"
    ln -s "../lib/llama.cpp/$name" "$root/usr/bin/$name"
done

# -type f leaves the soname symlinks alone, which is what we want.
find "$libdir" -name '*.so*' -type f -exec chmod 644 {} +

cat > "$root/DEBIAN/control" <<EOF
Package: llama-cpp
Version: ${version}
Architecture: ${arch}
Maintainer: li-ruijie <1547237+li-ruijie@users.noreply.github.com>
Homepage: https://github.com/ggml-org/llama.cpp
Depends: libc6 (>= 2.34), libgcc-s1, libgomp1, libstdc++6 (>= 12), libssl3t64 | libssl3
Conflicts: llama.cpp-tools, llama.cpp-tools-extra
Section: misc
Priority: optional
Description: llama.cpp, LLM inference in C/C++
 Command line tools and an HTTP server for running GGUF language models on
 CPU, repackaged from the upstream release archive.
 .
 Install llama-cpp-cuda alongside this package to add NVIDIA GPU
 acceleration.
EOF

deb="$outdir/llama-cpp_${version}_${arch}.deb"
dpkg-deb --root-owner-group --build "$root" "$deb" >/dev/null
echo "$deb"

#!/usr/bin/env bash
# Assemble llama-cpp-vulkan_<version>_<arch>.deb from upstream's Vulkan archive.
#
# The backend links libggml-base.so.1 from the base package, which is built from
# upstream's CPU archive. The two archives come from separate upstream builds,
# so the backend ships only when the Vulkan archive is the CPU archive plus
# libggml-vulkan.so, with every shared file byte-identical. Anything else could
# pair the backend with a libggml-base it was not built against.
set -euo pipefail

if [ "$#" -ne 5 ]; then
    echo "usage: $0 <vulkan-tarball> <cpu-tarball> <version> <arch> <outdir>" >&2
    exit 2
fi

vulkan=$1
cpu=$2
version=$3
arch=$4
outdir=$5

staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT

# Each archive holds every file under a single llama-b<N>/ directory.
mkdir "$staging/vk" "$staging/cpu"
tar xzf "$vulkan" -C "$staging/vk" --strip-components=1
tar xzf "$cpu" -C "$staging/cpu" --strip-components=1

listing() {  # listing <dir>
    (cd "$1" && find . -mindepth 1 | LC_ALL=C sort)
}

added=$(LC_ALL=C comm -13 <(listing "$staging/cpu") <(listing "$staging/vk"))
removed=$(LC_ALL=C comm -23 <(listing "$staging/cpu") <(listing "$staging/vk"))

indent() {  # indent <newline-separated list>, written to stderr
    printf '%s\n' "$1" | sed 's/^/  /' >&2
}

if [ "$added" != "./libggml-vulkan.so" ]; then
    echo "$0: the Vulkan archive must add only libggml-vulkan.so, it adds:" >&2
    indent "${added:-(nothing)}"
    exit 1
fi
if [ -n "$removed" ]; then
    echo "$0: the Vulkan archive lacks files the CPU archive has:" >&2
    indent "$removed"
    exit 1
fi

backend="$staging/vk/libggml-vulkan.so"
if [ ! -f "$backend" ] || [ -L "$backend" ]; then
    echo "$0: libggml-vulkan.so is not a regular file" >&2
    exit 1
fi

differing=""
while IFS= read -r path; do
    a="$staging/cpu/$path"
    b="$staging/vk/$path"
    if [ -L "$a" ] || [ -L "$b" ]; then
        if ! [ -L "$a" ] || ! [ -L "$b" ] || [ "$(readlink "$a")" != "$(readlink "$b")" ]; then
            differing="${differing:+$differing$'\n'}$path"
        fi
    elif [ -f "$a" ]; then
        cmp -s "$a" "$b" || differing="${differing:+$differing$'\n'}$path"
    fi
done < <(LC_ALL=C comm -12 <(listing "$staging/cpu") <(listing "$staging/vk"))

if [ -n "$differing" ]; then
    echo "$0: these files differ between the CPU and Vulkan archives:" >&2
    indent "$differing"
    exit 1
fi

root="$staging/root"
mkdir -p "$root/DEBIAN" "$root/usr/lib/llama.cpp"

# dpkg-deb rejects a control directory outside 0755 to 0775.
chmod 0755 "$root/DEBIAN"

install -m 644 "$backend" "$root/usr/lib/llama.cpp/libggml-vulkan.so"

cat > "$root/DEBIAN/control" <<EOF
Package: llama-cpp-vulkan
Version: ${version}
Architecture: ${arch}
Maintainer: li-ruijie <1547237+li-ruijie@users.noreply.github.com>
Homepage: https://github.com/ggml-org/llama.cpp
Depends: llama-cpp (= ${version}), libvulkan1
Recommends: vulkan-icd
Section: misc
Priority: optional
Description: llama.cpp, Vulkan backend
 Vulkan backend for llama-cpp, taken from the upstream Vulkan release
 archive. It runs on any GPU with a Vulkan driver, including AMD, Intel,
 and NVIDIA hardware.
 .
 The driver is recommended through the vulkan-icd virtual package, which
 mesa-vulkan-drivers and the NVIDIA Vulkan driver both provide. Where no
 driver is present, ggml skips the backend and llama-cpp runs on CPU.
 .
 With llama-cpp-cuda also installed, an NVIDIA GPU appears once per backend
 in llama-cli --list-devices. llama.cpp loads a model onto it once, through
 CUDA, and skips the Vulkan entry with the same device id.
EOF

deb="$outdir/llama-cpp-vulkan_${version}_${arch}.deb"
dpkg-deb --root-owner-group --build "$root" "$deb" >/dev/null
echo "$deb"

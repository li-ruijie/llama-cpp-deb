#!/usr/bin/env bash
# Resolve an upstream llama.cpp release pair into the values the build needs.
#
# Upstream splits its releases in two. A vX.Y.Z tag marks a stable version and
# carries no binaries, while a b<N> tag marks a nightly and carries the prebuilt
# Ubuntu archives. A stable release names its matching nightly in a
# nightly-tag.txt asset, and the two are the same commit, so the CUDA backend
# compiled from the stable source agrees with the base binaries repackaged from
# the nightly archive.
#
# Both tags are validated here rather than downstream. An unrecognised tag used to
# flow through into a nonsense package version and surface only at the archive
# download, after a full CUDA build had already been paid for.
set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "usage: $0 <stable-tag> <nightly-tag>" >&2
    exit 2
fi

stable=$1
nightly=$2

if [[ ! $stable =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "$0: stable tag must look like v0.2.0, got '$stable'" >&2
    exit 2
fi

if [[ ! $nightly =~ ^b[0-9]+$ ]]; then
    echo "$0: nightly tag must look like b10566, got '$nightly'" >&2
    exit 2
fi

# Debian versions must begin with a digit, which stripping the v leaves. Ordering
# carries over from the old 0.0.<build> scheme, since 0.2.0 sorts above 0.0.10453.
# The strict shapes above also keep these safe for the caller to source.
printf 'tag=%s\nnightly=%s\nversion=%s\n' "$stable" "$nightly" "${stable#v}"

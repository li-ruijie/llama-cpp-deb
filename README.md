# llama.cpp Debian packages

Builds `llama-cpp` and `llama-cpp-cuda` for the APT repository at
https://li-ruijie.github.io/apt/. Upstream publishes no Linux CUDA binaries, so the
CUDA backend is compiled here.

## Packages

┌──────────────────┬───────────────┬──────────────────────────────────────────────────┐
│ Package          │ Architectures │ Contents                                         │
├──────────────────┼───────────────┼──────────────────────────────────────────────────┤
│ llama-cpp        │ amd64, arm64  │ repackaged upstream archive, CPU backends        │
│ llama-cpp-cuda   │ amd64         │ libggml-cuda.so for CUDA acceleration            │
└──────────────────┴───────────────┴──────────────────────────────────────────────────┘

Everything installs under `/usr/lib/llama.cpp/`, with tools reached through symlinks in
`/usr/bin`.

## CUDA requirements

`llama-cpp-cuda` declares no CUDA dependency, so it installs anywhere. The backend loads
only when the machine provides all of the following.

- `libcudart.so.13` and `libcublas.so.13`, from NVIDIA's CUDA apt repository. Debian's own
  `nvidia-cuda-toolkit` is 12.4 and is too old.
- An NVIDIA driver of the 580 series or newer, which CUDA 13 requires.
- A GPU of compute capability 8.9 or 12.0. Other cards fall back to JIT from the shipped
  9.0 PTX.

When any of these is missing, ggml skips the backend and `llama-cpp` runs on CPU. Confirm
which backend is active with `llama-cli --list-devices`.

## Building

The workflow runs weekly and can be dispatched manually with a `version` override and a
`force` flag. The packaging scripts run standalone:

```sh
scripts/package-base.sh <tarball> <version> <arch> <outdir>
scripts/package-cuda.sh <libggml-cuda.so> <version> <outdir>
scripts/smoke-test.sh <base.deb> <cuda.deb>
```

Upstream llama.cpp is MIT licensed. Its `LICENSE` ships in the base package at
`/usr/share/doc/llama-cpp/copyright`.

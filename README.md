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

`llama-cpp-cuda` depends on the CUDA runtime, so apt installs it automatically:

```
Depends: llama-cpp (= <version>), cuda-cudart-13-3, libcublas-13-3
```

The suffix tracks whichever toolkit the backend was compiled against, derived from `nvcc`
at build time, so a container bump moves the dependency with it.

Those packages come from **NVIDIA's own CUDA apt repository**, which has to be configured
on the target machine. Debian's `nvidia-cuda-toolkit` is 12.4, which is both too old for
compute capability 12.0 and the wrong soname for a CUDA 13 build, so it cannot satisfy
this. Without NVIDIA's repository, `apt install llama-cpp-cuda` fails with an unsatisfiable
dependency rather than installing something that cannot work.

Two things are still not expressed as dependencies.

- **The driver.** A 580 series or newer is required, but its package name varies across
  distributions, so depending on it would break portability for no gain. The GPU is
  unusable without a driver regardless.
- **The GPU itself.** Compute capability 8.9 or 12.0 gets native device code. Other cards
  fall back to JIT from the shipped 9.0 PTX.

Where the driver or a suitable GPU is missing, ggml skips the backend and `llama-cpp` runs
on CPU. Confirm which backend is active with `llama-cli --list-devices`, and if it reports
none, `ldd /usr/lib/llama.cpp/libggml-cuda.so | grep 'not found'` names the cause.

## Building

The workflow runs weekly and can be dispatched manually with a `version` override and a
`force` flag. The packaging scripts run standalone:

```sh
scripts/package-base.sh <tarball> <version> <arch> <outdir>
scripts/package-cuda.sh <libggml-cuda.so> <version> <cuda-suffix> <outdir>
scripts/smoke-test.sh <base.deb> [cuda.deb]
```

`cuda-suffix` is the CUDA release in NVIDIA's apt naming, so 13.3 becomes `13-3`.

Upstream llama.cpp is MIT licensed. Its `LICENSE` ships in the base package at
`/usr/share/doc/llama-cpp/copyright`.

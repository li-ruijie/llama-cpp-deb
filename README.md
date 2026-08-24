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

These are the exact two runtime packages the backend links. NVIDIA's `cuda-libraries`
metapackage would also work and would need no maintenance, but it pulls 13 packages and
about 1.2 GB, of which llama.cpp uses two. The pin is kept honest by
`scripts/check-backend-deps.sh`, which reads the compiled backend's `DT_NEEDED` entries
and fails the build if any CUDA library outside the declared set appears.

That check matters because nothing else would catch the drift. Every CUDA library is
present in the build container, so a newly linked one resolves there and the smoke test
stays green. It would surface only on a user's machine, as a backend that fails to load
and a silent fall back to CPU. That is what the NCCL link caused once already.

The bare `cuda` metapackage is deliberately avoided, since it depends on `nvidia-open` and
would pull a competing driver onto a machine using a distribution-packaged one.

Those packages come from **NVIDIA's own CUDA apt repository**, which has to be configured
on the target machine. Debian's `nvidia-cuda-toolkit` is 12.4, which is both too old for
compute capability 12.0 and the wrong soname for a CUDA 13 build, so it cannot satisfy
this. Without NVIDIA's repository, `apt install llama-cpp-cuda` fails with an unsatisfiable
dependency rather than installing something that cannot work.

Two requirements are still not expressed as dependencies.

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
`force` flag.

Upstream publishes two kinds of release. A `vX.Y.Z` tag marks a stable version and carries
no binaries, while a `b<N>` tag marks a nightly and carries the prebuilt Ubuntu archives.
These packages follow the stable line, which is what upstream recommends for downstream
distribution, so the package version is the stable tag without its leading `v`. Every
stable release names its matching nightly in a `nightly-tag.txt` asset, and the two are the
same commit, so the CUDA backend compiled from the stable source agrees with the base
binaries repackaged from the nightly archive.

The packaging scripts run standalone:

```sh
scripts/resolve-upstream.sh <stable-tag> <nightly-tag>
scripts/package-base.sh <tarball> <version> <arch> <outdir>
scripts/package-cuda.sh <libggml-cuda.so> <version> <cuda-suffix> <outdir>
scripts/check-backend-deps.sh <libggml-cuda.so | ->
scripts/smoke-test.sh <base.deb> [cuda.deb]
```

`resolve-upstream.sh` validates both tags and prints the `tag`, `nightly`, and `version`
the workflow uses. `cuda-suffix` is the CUDA release in NVIDIA's apt naming, so 13.3
becomes `13-3`.

Upstream llama.cpp is MIT licensed. Its `LICENSE` ships in the base package at
`/usr/share/doc/llama-cpp/copyright`.

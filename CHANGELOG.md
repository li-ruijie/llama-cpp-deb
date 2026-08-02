# Changelog

┌────────────┬──────────────────────────────────────────────────────────────────────────────────┐
│ Date       │ Summary                                                                          │
├────────────┼──────────────────────────────────────────────────────────────────────────────────┤
│ 2026-08-02 │ llama-cpp-cuda 0.0.10223 live for amd64, libggml-cuda.so compiled against CUDA   │
│            │ 13.3.1 for 89-real, 120a-real, and 90-virtual, 51.8 MB packaged                  │
│ 2026-08-02 │ Turned GGML_CUDA_NCCL off. It defaults on and the build container ships NCCL, so │
│            │ the backend linked libnccl.so.2, which target machines lack. The backend would   │
│            │ have failed to dlopen and ggml would have fallen back to CPU without saying why  │
│ 2026-08-01 │ llama-cpp 0.0.10218 live in the APT repository for amd64 and arm64, repackaged   │
│            │ from the upstream Ubuntu archive with its 23 tools symlinked into /usr/bin       │
│ 2026-08-01 │ Initial scaffold                                                                 │
└────────────┴──────────────────────────────────────────────────────────────────────────────────┘

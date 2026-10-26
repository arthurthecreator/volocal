# Volocal

Fully local voice AI for iOS. No cloud, no API keys, no internet after setup.

STT → LLM → TTS, streaming in real-time on your iPhone.

[<img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="Download on the App Store" height="50">](https://apps.apple.com/app/volocal/id6761493288)

> **Note:** This is a work in progress. Expect bugs.

[![Demo video](assets/thumbnail.jpg)](https://www.fikrikarim.com/volocal/volocal.mp4)

# Why?

I'm [self-hosting a totally free voice AI](https://www.fikrikarim.com/bule-ai-initial-release/) on my home server to help people learn speaking English. It has tens to hundreds of monthly active users, and I've been thinking on how to keep it free while making it sustainable.

The ultimate way to reduce the operational costs is to run everything on-device, eliminating any server cost. I thought this was impossible at first, given that 6 months ago I needed an RTX 5090 to run these models in real-time.

So I decided to replicate the voice AI experience to fully run locally on my iPhone 15, and to my surprise, it's working better than I expected.

## Features

- Runs entirely on-device across Neural Engine, GPU, and CPU
- Real-time voice conversations
- Interrupt mid-sentence (barge-in)
- Hardware echo cancellation so the mic doesn't pick up its own output
- Language model is included in the app (fetched when you build; not stored in git)
- Speech models (~1.05 GB) download on first launch with per-model progress

## Why this stack

The hard part of running three models at once on a phone is that they all fight for the same hardware. We spread the load across different compute units:

| Component              | Chip          | Why                                                      |
| ---------------------- | ------------- | -------------------------------------------------------- |
| **STT** (Parakeet EOU) | Neural Engine | CoreML — leaves GPU and CPU free                         |
| **LLM** (Qwen3.5-2B)   | GPU           | llama.cpp via Metal, gets the GPU to itself              |
| **TTS** (PocketTTS)    | CPU + GPU     | CoreML — ANE causes float16 artifacts in Mimi decoder    |

We started with [mlx-audio-swift](https://github.com/Blaizzy/mlx-audio-swift) for TTS, which uses the GPU via MLX. That meant TTS and the LLM were both competing for Metal, causing dropouts and hangs during streaming. Similarly, we tried [Moonshine](https://github.com/usefulsensors/moonshine) for STT — a promising streaming model, but it also runs on GPU/CPU via ONNX Runtime, adding to the contention and using more memory.

Moving STT to [FluidAudio](https://github.com/FluidInference/FluidAudio) (CoreML/Neural Engine) and TTS to FluidAudio (CoreML/CPU+GPU) fixed the contention and significantly reduced memory usage.

### Models

| Component | Model                                                                                       | How you get it | Runtime           |
| --------- | ------------------------------------------------------------------------------------------- | -------------- | ----------------- |
| STT       | [Parakeet EOU 320](https://huggingface.co/FluidInference/parakeet-realtime-eou-120m-coreml) | Runtime download, ~450 MB | CoreML (ANE)      |
| LLM       | [Qwen3.5-2B Q4_K_S](https://huggingface.co/bartowski/Qwen_Qwen3.5-2B-GGUF)                  | Bundled at build time, 1,327,696,992 bytes | llama.cpp (Metal), ctx 8192, KV q8_0 |
| TTS       | [PocketTTS](https://huggingface.co/FluidInference/pocket-tts-coreml)                        | Runtime download, ~600 MB | CoreML (CPU+GPU)  |

Why these specifically:

- **Parakeet EOU** over Moonshine/Whisper — lower WER (4.87% vs 6.65% Moonshine Medium), half the parameters, and end-of-utterance detection is built into the model so you don't need a separate VAD.
- **Qwen3.5-2B** over 0.8B — MMLU-Pro nearly doubles (29.7 → 55.3). Slower (~32 vs ~70 tok/s) but the quality difference is obvious in conversation. Q4_K_S is 1,327,696,992 bytes. Context is fixed at 8192 with K and V quantized to q8_0.
- **PocketTTS** — best quality we found at this size (100M params). ~80ms to first audio, supports voice cloning from a 5-second clip.

### Audio

One shared `AVAudioEngine` for both STT input and TTS output, with Voice Processing AEC enabled on both nodes. This is what lets barge-in work — the mic stays open during playback and the hardware cancels the echo, so there's no need to mute the mic while speaking.

Runtime memory was about 1.2 GB total at context 2048 (iPhone 15 budget is ~3 GB). Context is now 8192 with a q8_0 K/V cache. For this model that cache is on the order of a few tens of MB and has not been remeasured on a device.

## Getting started

You need iOS 17+, Xcode 16+, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). Physical device only — the Neural Engine isn't available in the simulator.

```bash
git clone https://github.com/fikrikarim/volocal.git
cd volocal
xcodegen generate
open Volocal.xcodeproj
```

The Xcode target has a **Fetch bundled LLM GGUF** build phase (`scripts/fetch_llm_gguf.sh`). On the first build it downloads the GGUF from Hugging Face into `Volocal/Resources/LLM/`, checks the SHA-256 in `scripts/llm-gguf.lock`, and Xcode copies that folder into the app. Later builds skip the download when the file already matches. The GGUF is gitignored, so it is never committed.

You can fetch it yourself before opening Xcode:

```bash
./scripts/fetch_llm_gguf.sh
```

Build and run on a device. The language model is already in the app. Tap **Download Speech Models** on first launch for Parakeet and PocketTTS (~1.05 GB, Wi-Fi recommended).

### Bundled language model

| | |
| --- | --- |
| File | `Qwen_Qwen3.5-2B-Q4_K_S.gguf` |
| Source | [bartowski/Qwen_Qwen3.5-2B-GGUF](https://huggingface.co/bartowski/Qwen_Qwen3.5-2B-GGUF) (imatrix quant of [Qwen/Qwen3.5-2B](https://huggingface.co/Qwen/Qwen3.5-2B)) |
| Size | 1,327,696,992 bytes (about 1.24 GiB) |
| SHA-256 | `55b574899b75180d084238ffbf5d3d165c568a3d73e1edbd3c826682a986c8d4` |
| Lockfile | `scripts/llm-gguf.lock` (must match `ModelRegistry.llmFilename`) |
| Runtime | context **8192**, K and V cache **q8_0**, Flash Attention on (required for a quantized V cache) |

The build machine needs to reach `huggingface.co` the first time, and again whenever the lockfile changes. A checksum or size mismatch fails the build instead of bundling a partial file.

Apple's uncompressed app limit is 4 GB. This GGUF is about 1.24 GiB. The app binary and frameworks are tens of MB on top of that (not measured here; this environment has no Xcode). Speech models are **not** in the bundle: Parakeet (~450 MB) is downloaded into the app's Documents directory by FluidAudio, and PocketTTS (~600 MB) is downloaded into `Library/Caches/fluidaudio`. After setup the phone holds roughly 2.4 GB of models, and the App Store binary itself stays near 1.3 GB, under the 4 GB limit. A build this large will usually install over Wi-Fi.

## Architecture

```
Mic → [SharedAudioEngine] → STTManager → VoicePipeline → LLMManager → SentenceBuffer → TTSManager → Speaker
                                              ↑                                              |
                                              └──── barge-in (interrupt on speech) ──────────┘
```

- **SharedAudioEngine** — one `AVAudioEngine` shared by STT and TTS, with VP AEC on both input and output nodes.
- **VoicePipeline** — runs the loop. Turn revision guards prevent stale tasks from messing things up after a barge-in. LLM tokens stream through a sentence buffer so TTS can start before generation finishes.
- **SentenceBuffer** — splits streaming text at `.!?:;` boundaries (max 200 chars) so each TTS chunk stays short.

## Project structure

```
Volocal/
├── App/        # Entry point, content view, model loading
├── Audio/      # SharedAudioEngine (AVAudioEngine + VP AEC)
├── STT/        # Parakeet EOU via FluidAudio
├── LLM/        # llama.cpp via llama.swift
├── TTS/        # PocketTTS via FluidAudio
├── Pipeline/   # Voice pipeline, sentence buffer, conversation UI
├── Models/     # Model registry, download manager, onboarding
└── Debug/      # Metrics overlay (RAM, CPU, thermal)
```

## Dependencies

- [llama.swift](https://github.com/mattt/llama.swift) — Swift wrapper for llama.cpp
- [FluidAudio](https://github.com/FluidInference/FluidAudio) — Parakeet EOU (STT) and PocketTTS (TTS)

Both pulled in via SPM.

## TODO

- [ ] Add [Apple Foundation Models](https://developer.apple.com/documentation/FoundationModels) as an LLM option (iOS 26+)
- [ ] Android support (might be far in the future)

## Acknowledgements

- [FluidAudio](https://github.com/FluidInference/FluidAudio) by FluidInference — CoreML implementations of Parakeet EOU and PocketTTS that make the Neural Engine strategy possible
- [llama.swift](https://github.com/mattt/llama.swift) by Mattt — clean Swift bindings for llama.cpp
- [llama.cpp](https://github.com/ggml-org/llama.cpp) by ggml — the LLM inference engine
- [Qwen3.5](https://huggingface.co/Qwen/Qwen3.5-2B) by Qwen — the language model
- [Parakeet EOU](https://huggingface.co/nvidia/parakeet-tdt_ctc-110m) by NVIDIA NeMo — the speech recognition model
- [PocketTTS](https://github.com/kyutai-labs/pocket-tts) by Kyutai — the text-to-speech model

## License

MIT

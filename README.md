# Volocal

Fully local voice AI for iOS. No cloud, no API keys, no internet connection required to run.

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
- Language, speech recognition, and text-to-speech models are included in the app (fetched when you build; not stored in git)
- No model download on first launch

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
| STT       | [Parakeet EOU 320](https://huggingface.co/FluidInference/parakeet-realtime-eou-120m-coreml) | Bundled at build time, 224,238,533 bytes | CoreML (ANE)      |
| LLM       | [Qwen3.5-2B Instruct Q4_K_M](https://huggingface.co/bartowski/Qwen_Qwen3.5-2B-GGUF)         | Bundled at build time, 1,396,198,496 bytes | llama.cpp (Metal), ctx 2048, KV F16 |
| TTS       | [PocketTTS](https://huggingface.co/FluidInference/pocket-tts-coreml)                        | Bundled at build time, 732,524,727 bytes | CoreML (CPU+GPU)  |

Why these specifically:

- **Parakeet EOU** over Moonshine/Whisper — lower WER (4.87% vs 6.65% Moonshine Medium), half the parameters, and end-of-utterance detection is built into the model so you don't need a separate VAD.
- **Qwen3.5-2B** over 0.8B — MMLU-Pro nearly doubles (29.7 → 55.3). Slower (~32 vs ~70 tok/s) but the quality difference is obvious in conversation. The bundled quant is Q4_K_M (1,396,198,496 bytes) of the official post-trained model, which is the instruct checkpoint. Qwen does not ship a separate `-Instruct` repo. Context is fixed at 2048 with an F16 K/V cache (latency A/B step 1).
- **PocketTTS** — best quality we found at this size (100M params). ~80ms to first audio, supports voice cloning from a 5-second clip.

### Audio

One shared `AVAudioEngine` for both STT input and TTS output, with Voice Processing AEC enabled on both nodes. This is what lets barge-in work — the mic stays open during playback and the hardware cancels the echo, so there's no need to mute the mic while speaking.

Runtime memory was about 1.2 GB total at context 2048 (iPhone 15 budget is ~3 GB). Context is back to 2048 with an F16 K/V cache (latency A/B step 1).

## Getting started

You need iOS 17+, Xcode 16+, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). Physical device only — the Neural Engine isn't available in the simulator.

```bash
git clone https://github.com/fikrikarim/volocal.git
cd volocal
xcodegen generate
open Volocal.xcodeproj
```

The Xcode target has two pre-build phases, **Fetch bundled LLM GGUF** (`scripts/fetch_llm_gguf.sh`) and **Fetch bundled speech models** (`scripts/fetch_audio_models.sh`). On the first build they download the files from Hugging Face into `Volocal/Resources/LLM/` and `Volocal/Resources/Audio/`, check every SHA-256 in `scripts/llm-gguf.lock` and `scripts/audio-models.lock`, and Xcode copies those folders into the app. Later builds skip a file when its size and checksum already match. The payloads are gitignored, so they are never committed.

You can fetch them yourself before opening Xcode:

```bash
./scripts/fetch_llm_gguf.sh
./scripts/fetch_audio_models.sh
```

Build and run on a device. All three models are already in the app. There is no first-launch download. If a bundled file is missing, the app stops with an error and does not use the network.

### Bundled language model

| | |
| --- | --- |
| File | `Qwen_Qwen3.5-2B-Q4_K_M.gguf` |
| Source | [bartowski/Qwen_Qwen3.5-2B-GGUF](https://huggingface.co/bartowski/Qwen_Qwen3.5-2B-GGUF) (imatrix Q4_K_M of the post-trained [Qwen/Qwen3.5-2B](https://huggingface.co/Qwen/Qwen3.5-2B) instruct model) |
| Size | 1,396,198,496 bytes (about 1.30 GiB) |
| SHA-256 | `57a1085840f497d764a7fc5d346922dbde961efb54cc792ea81d694fd846a1d8` |
| Lockfile | `scripts/llm-gguf.lock` (must match `ModelRegistry.llmFilename`) |
| Runtime | context **2048**, K and V cache **F16**, Flash Attention on (kept from the q8_0 setup; not required with F16) |

The prompt ends with the official non-thinking prefix from `Qwen/Qwen3.5-2B`'s chat template (an assistant header plus an empty think block). Generation stops on the GGUF eos token `<|im_end|>` (id 248046) through `llama_vocab_is_eog`.

### Bundled speech models

`scripts/fetch_audio_models.sh` reads `scripts/audio-models.lock` (107 files, 956,763,260 bytes) and writes them under `Volocal/Resources/Audio/`. The app loads those files from the bundle. If CoreML cannot read a compiled model out of the read-only bundle, the app copies that tree once and loads the copy: Parakeet goes to `Documents/models/parakeet-eou-streaming/320ms`, and PocketTTS goes to `Library/Caches/fluidaudio/Models/pocket-tts` (FluidAudio's default cache). That copy does not use the network.

| | Parakeet EOU 320 | PocketTTS |
| --- | --- | --- |
| Source | [FluidInference/parakeet-realtime-eou-120m-coreml](https://huggingface.co/FluidInference/parakeet-realtime-eou-120m-coreml) `320ms/` | [FluidInference/pocket-tts-coreml](https://huggingface.co/FluidInference/pocket-tts-coreml) |
| Files | 17 | 90 |
| Size | 224,238,533 bytes | 732,524,727 bytes |
| Lockfile | `scripts/audio-models.lock` | `scripts/audio-models.lock` |
| Bundle path | `Audio/STT/parakeet-eou-streaming/320ms` | `Audio/TTS` (`Models/pocket-tts` underneath) |

The Parakeet set is what FluidAudio's `downloadRepo(.parakeetEou320)` keeps: `streaming_encoder.mlmodelc`, `decoder.mlmodelc`, `joint_decision.mlmodelc`, `vocab.json`, and `streaming_encoder_metadata.json`. The duplicate `.mlpackage` trees are not included. PocketTTS is the set `PocketTtsResourceDownloader.ensureModels` expects at FluidAudio commit `b0a3eeec` (fikrikarim/FluidAudio `main`), including the eight built-in voice prompts. The optional voice-cloning model `mimi_encoder.mlmodelc` is not part of that set and is not bundled. The conversation pipeline does not call it. That unused API would still try to download the encoder.

Every file's URL, byte size, and SHA-256 is in the lockfile. The fetch script checks them before the app is signed. A mismatch fails the build.

The build machine needs to reach `huggingface.co` the first time, and again whenever a lockfile changes. A checksum or size mismatch fails the build instead of bundling a partial file.

Apple's uncompressed app limit is 4 GB (4,294,967,296 bytes). The three model payloads together are 2,352,961,756 bytes (2.191 GiB): the Q4_K_M GGUF at 1,396,198,496 bytes plus 956,763,260 bytes of speech models. That leaves 1,942,005,540 bytes (1.809 GiB) for the app binary, frameworks, and assets, which were not measured here (this environment has no Xcode). The total stays under 4 GB. An app this large will usually install over Wi-Fi.

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
├── Models/     # Model registry and missing-bundle screen
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

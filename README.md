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
- Loads models from the app Documents directory or the app bundle. No in-app download.

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

| Component | Model                                                                                       | Size                         | Runtime           |
| --------- | ------------------------------------------------------------------------------------------- | ---------------------------- | ----------------- |
| STT       | [Parakeet EOU 320](https://huggingface.co/FluidInference/parakeet-realtime-eou-120m-coreml) | ~450 MB                      | CoreML (ANE)      |
| LLM       | [Qwen3.5-2B Q4_K_M](https://huggingface.co/bartowski/Qwen_Qwen3.5-2B-GGUF)                  | 1.40 GB (1,396,198,496 bytes) | llama.cpp (Metal) |
| TTS       | [PocketTTS](https://huggingface.co/FluidInference/pocket-tts-coreml)                        | ~600 MB                      | CoreML (CPU+GPU)  |

Why these specifically:

- **Parakeet EOU** over Moonshine/Whisper — lower WER (4.87% vs 6.65% Moonshine Medium), half the parameters, and end-of-utterance detection is built into the model so you don't need a separate VAD.
- **Qwen3.5-2B** over 0.8B — MMLU-Pro nearly doubles (29.7 → 55.3). Slower (~32 vs ~70 tok/s) but the quality difference is obvious in conversation. This fork uses bartowski `Qwen_Qwen3.5-2B-Q4_K_M.gguf` (1,396,198,496 bytes, listed as 1.40 GB on the Hugging Face file table). Context is 8192 with a Q8_0 K/V cache; see [README_FORK.md](README_FORK.md).
- **PocketTTS** — best quality we found at this size (100M params). ~80ms to first audio, supports voice cloning from a 5-second clip.

### Audio

One shared `AVAudioEngine` for both STT input and TTS output, with Voice Processing AEC enabled on both nodes. This is what lets barge-in work — the mic stays open during playback and the hardware cancels the echo, so there's no need to mute the mic while speaking.

Upstream measured about 1.2 GB with `n_ctx` 2048. This fork uses `n_ctx` 8192 and a Q8_0 KV cache, so that figure is not the budget to plan against. The iPhone 15 jetsam ceiling cited upstream is still about 3 GB. See [README_FORK.md](README_FORK.md).

## Getting started

You need iOS 17+, Xcode 16+, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). Physical device only — the Neural Engine isn't available in the simulator.

```bash
git clone https://github.com/fikrikarim/volocal.git
cd volocal
xcodegen generate
open Volocal.xcodeproj
```

The app does not download weights. Copy the files below into the app container (or ship them in the bundle) before the first conversation. Device commands, Finder, and `devicectl` are in [README_FORK.md](README_FORK.md).

## Model files

Nothing is fetched from Hugging Face at runtime. If a file is missing, the first screen names it and the folder to copy it into. The same relative path is also accepted inside the `.app` bundle.

Finder file sharing shows the app **Documents** directory as its root (`UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace`). Paths below are relative to that root, and to the data container for `devicectl`. Bundle id: `com.fikrikarim.volocal`.

`Documents/models` and `Documents/Models` are different directories. PocketTTS must use the capital **Models**, because FluidAudio appends `PocketTtsConstants.defaultModelsSubdirectory` (`"Models"`).

### LLM — Qwen3.5-2B Q4_K_M

- Source: [bartowski/Qwen_Qwen3.5-2B-GGUF](https://huggingface.co/bartowski/Qwen_Qwen3.5-2B-GGUF)
- File: `Qwen_Qwen3.5-2B-Q4_K_M.gguf`
- Size: **1,396,198,496 bytes** (1.40 GB on the Hugging Face table; LFS oid `57a1085840f497d764a7fc5d346922dbde961efb54cc792ea81d694fd846a1d8`)
- Documents: `models/Qwen_Qwen3.5-2B-Q4_K_M.gguf`
- Bundle: `models/Qwen_Qwen3.5-2B-Q4_K_M.gguf`
- A file with another size is rejected and reported. It is not loaded.

### STT — Parakeet EOU 320

- Source: [FluidInference/parakeet-realtime-eou-120m-coreml](https://huggingface.co/FluidInference/parakeet-realtime-eou-120m-coreml), subdirectory `320ms/`
- Copy the compiled models, not the `.mlpackage` or the conversion scripts
- Documents and bundle, under `models/parakeet-eou-streaming/320ms/` (FluidAudio's `Repo.parakeetEou320.folderName`, which is not the Hugging Face folder name):
  - `streaming_encoder.mlmodelc/`
  - `decoder.mlmodelc/`
  - `joint_decision.mlmodelc/`
  - `vocab.json`
- `streaming_encoder_metadata.json` is not read by `StreamingEouAsrManager.loadModels`

### TTS — PocketTTS

- Source: [FluidInference/pocket-tts-coreml](https://huggingface.co/FluidInference/pocket-tts-coreml), **repository root** (the `v2/<lang>/` tree is a different layout and will not be found)
- Documents and bundle, under `Models/pocket-tts/`:
  - `cond_step.mlmodelc/`
  - `flowlm_step.mlmodelc/`
  - `flow_decoder.mlmodelc/`
  - `mimi_decoder_v2.mlmodelc/`
  - `constants_bin/` copied as a whole directory, including `mimi_init_state/`
- The app refuses to start TTS unless these are present (a missing file would make FluidAudio download it):
  - `constants_bin/bos_emb.bin`
  - `constants_bin/text_embed_table.bin`
  - `constants_bin/tokenizer.model`
  - `constants_bin/manifest.json`
  - `constants_bin/mimi_init_state/attn0_cache.bin`
  - `constants_bin/alba_audio_prompt.bin`
  - `constants_bin/marius_audio_prompt.bin`
  - `constants_bin/javert_audio_prompt.bin`
  - `constants_bin/jean_audio_prompt.bin`
  - `constants_bin/fantine_audio_prompt.bin`
  - `constants_bin/cosette_audio_prompt.bin`
  - `constants_bin/eponine_audio_prompt.bin`
  - `constants_bin/azelma_audio_prompt.bin`
- `mimi_encoder.mlmodelc` is only used for voice cloning. This app does not call that path.

`mimi_decoder.mlmodelc` (without `_v2`) is not the file FluidAudio loads. The required decoder is `mimi_decoder_v2.mlmodelc`.

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
├── Models/     # Model registry and on-disk checks (no downloader)
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

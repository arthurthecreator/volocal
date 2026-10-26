# Point Barre — fork de Volocal

Fork de [fikrikarim/volocal](https://github.com/fikrikarim/volocal) (MIT). Remote de ce dépôt : `https://github.com/arthurthecreator/volocal`.

iOS 17+, Xcode 16+, [XcodeGen](https://github.com/yonaskolb/XcodeGen). Appareil physique uniquement : le Neural Engine n’existe pas dans le simulateur.

Ce document est le mode d’emploi du fork. La liste des fichiers est aussi dans [README.md](README.md).

**Build : non compilé ici.** L’agent cloud n’a pas Xcode. `xcodegen`, la compilation et l’installation sur l’iPhone sont faits par GROK sur le Mac.

## Commandes

```bash
brew install xcodegen
cd volocal
xcodegen generate
open Volocal.xcodeproj
```

Lister les appareils, compiler, installer (remplacer `UDID`) :

```bash
xcrun devicectl list devices

xcodebuild \
  -project Volocal.xcodeproj \
  -scheme Volocal \
  -destination 'id=UDID' \
  -configuration Debug \
  -allowProvisioningUpdates \
  -derivedDataPath build/DerivedData \
  build

xcrun devicectl device install app --device UDID \
  build/DerivedData/Build/Products/Debug-iphoneos/Volocal.app
```

Le chemin exact de `Volocal.app` est celui imprimé par `xcodebuild` (`touch` / `CodeSign`). Signature dans `project.yml` : `DEVELOPMENT_TEAM: CDMG5NRWRF`, bundle id `com.pointbarre.volocal` (`bundleIdPrefix: com.pointbarre`). Une cible de test générée ensuite prend le suffixe `.tests` sur ce préfixe.

## Copie des modèles

L’app ne contacte pas Hugging Face. Elle ouvre un fichier déjà présent dans **Documents**, sinon le même chemin relatif dans le bundle. S’il manque, l’écran d’accueil affiche le nom attendu et le dossier, et elle ne plante pas.

`UIFileSharingEnabled` et `LSSupportsOpeningDocumentsInPlace` sont activés. Dans le Finder, la racine « Fichiers » de Volocal **est** `Documents`.

Deux dossiers distincts, la casse compte (APFS) :

| Dossier | Contenu |
| --- | --- |
| `Documents/models/` | GGUF + Parakeet |
| `Documents/Models/` | PocketTTS (`Models` avec un M majuscule, imposé par `PocketTtsConstants.defaultModelsSubdirectory`) |

### Sur le Mac (pas dans l’app)

```bash
pip install -U "huggingface_hub"
hf download bartowski/Qwen_Qwen3.5-2B-GGUF \
  --include "Qwen_Qwen3.5-2B-Q4_K_M.gguf" \
  --local-dir ./hf/llm

hf download FluidInference/parakeet-realtime-eou-120m-coreml \
  --include "320ms/streaming_encoder.mlmodelc/**" \
  --include "320ms/decoder.mlmodelc/**" \
  --include "320ms/joint_decision.mlmodelc/**" \
  --include "320ms/vocab.json" \
  --local-dir ./hf/parakeet

hf download FluidInference/pocket-tts-coreml \
  --include "cond_step.mlmodelc/**" \
  --include "flowlm_step.mlmodelc/**" \
  --include "flow_decoder.mlmodelc/**" \
  --include "mimi_decoder_v2.mlmodelc/**" \
  --include "constants_bin/**" \
  --local-dir ./hf/pocket
```

Vérifier le GGUF avant copie : `stat -f%z hf/llm/Qwen_Qwen3.5-2B-Q4_K_M.gguf` doit afficher `1396198496`.

### Finder

1. Brancher l’iPhone, le déverrouiller, faire confiance à l’ordinateur.
2. Finder → l’iPhone → Fichiers → Volocal.
3. Créer `models` et `Models`.
4. Glisser :
   - `models/Qwen_Qwen3.5-2B-Q4_K_M.gguf`
   - `models/parakeet-eou-streaming/320ms/` contenant `streaming_encoder.mlmodelc`, `decoder.mlmodelc`, `joint_decision.mlmodelc`, `vocab.json` (les `.mlmodelc` sont des dossiers)
   - `Models/pocket-tts/` contenant les quatre `.mlmodelc` de la racine du repo PocketTTS et le dossier `constants_bin/` entier
5. Relancer l’app, ou revenir au premier plan : elle revérifie les fichiers. Sinon, toucher **Vérifier les fichiers**.

Le sous-dossier Hugging Face du Parakeet s’appelle `320ms/`. Sur l’appareil il doit s’appeler `models/parakeet-eou-streaming/320ms/` (`Repo.parakeetEou320.folderName`).

PocketTTS se copie depuis la **racine** de `FluidInference/pocket-tts-coreml`, pas depuis `v2/<langue>/`. Le décodeur lu par FluidAudio est `mimi_decoder_v2.mlmodelc`, pas `mimi_decoder.mlmodelc`.

### devicectl

`--destination` est relatif à la racine du conteneur (pas à Documents). `--domain-type appDataContainer` est obligatoire.

```bash
APP=com.pointbarre.volocal

xcrun devicectl device copy to \
  --device UDID \
  --source ./hf/llm/Qwen_Qwen3.5-2B-Q4_K_M.gguf \
  --destination Documents/models/Qwen_Qwen3.5-2B-Q4_K_M.gguf \
  --domain-type appDataContainer \
  --domain-identifier "$APP"

xcrun devicectl device copy to \
  --device UDID \
  --source ./hf/parakeet/320ms/streaming_encoder.mlmodelc \
  --destination Documents/models/parakeet-eou-streaming/320ms/streaming_encoder.mlmodelc \
  --domain-type appDataContainer \
  --domain-identifier "$APP"

xcrun devicectl device copy to \
  --device UDID \
  --source ./hf/parakeet/320ms/decoder.mlmodelc \
  --destination Documents/models/parakeet-eou-streaming/320ms/decoder.mlmodelc \
  --domain-type appDataContainer \
  --domain-identifier "$APP"

xcrun devicectl device copy to \
  --device UDID \
  --source ./hf/parakeet/320ms/joint_decision.mlmodelc \
  --destination Documents/models/parakeet-eou-streaming/320ms/joint_decision.mlmodelc \
  --domain-type appDataContainer \
  --domain-identifier "$APP"

xcrun devicectl device copy to \
  --device UDID \
  --source ./hf/parakeet/320ms/vocab.json \
  --destination Documents/models/parakeet-eou-streaming/320ms/vocab.json \
  --domain-type appDataContainer \
  --domain-identifier "$APP"

xcrun devicectl device copy to \
  --device UDID \
  --source ./hf/pocket/cond_step.mlmodelc \
  --destination Documents/Models/pocket-tts/cond_step.mlmodelc \
  --domain-type appDataContainer \
  --domain-identifier "$APP"

xcrun devicectl device copy to \
  --device UDID \
  --source ./hf/pocket/flowlm_step.mlmodelc \
  --destination Documents/Models/pocket-tts/flowlm_step.mlmodelc \
  --domain-type appDataContainer \
  --domain-identifier "$APP"

xcrun devicectl device copy to \
  --device UDID \
  --source ./hf/pocket/flow_decoder.mlmodelc \
  --destination Documents/Models/pocket-tts/flow_decoder.mlmodelc \
  --domain-type appDataContainer \
  --domain-identifier "$APP"

xcrun devicectl device copy to \
  --device UDID \
  --source ./hf/pocket/mimi_decoder_v2.mlmodelc \
  --destination Documents/Models/pocket-tts/mimi_decoder_v2.mlmodelc \
  --domain-type appDataContainer \
  --domain-identifier "$APP"

xcrun devicectl device copy to \
  --device UDID \
  --source ./hf/pocket/constants_bin \
  --destination Documents/Models/pocket-tts/constants_bin \
  --domain-type appDataContainer \
  --domain-identifier "$APP"
```

Si une copie échoue parce que le dossier parent n’existe pas, créer `models`, `Models` et `Models/pocket-tts` une fois dans le Finder, puis relancer. `xcrun devicectl device copy to --help` fait foi si une version de Xcode traite `--destination` comme un dossier plutôt que comme le chemin du fichier.

Fichiers que l’app exige dans `constants_bin/` avant d’appeler PocketTTS (sinon `ensureVoice` / `ensureModels` iraient sur Hugging Face) : `bos_emb.bin`, `text_embed_table.bin`, `tokenizer.model`, `manifest.json`, `mimi_init_state/attn0_cache.bin`, et les prompts `alba`, `marius`, `javert`, `jean`, `fantine`, `cosette`, `eponine`, `azelma` (`<voix>_audio_prompt.bin`). Copier le dossier `constants_bin/` entier, pas seulement ces sentinelles.

## Diff par rapport à l’upstream

Upstream pipeline : Parakeet EOU 320 (CoreML/ANE) → Qwen3.5-2B **Q4_K_S** via llama.cpp Metal (llama.swift) → PocketTTS CoreML, avec téléchargement au premier lancement.

Ce fork (en plus des commits déjà présents : team ID, fastlane, badge App Store) :

| Sujet | Upstream | Ici |
| --- | --- | --- |
| GGUF | `Qwen_Qwen3.5-2B-Q4_K_S.gguf`, affiché ~1,26 Go | `Qwen_Qwen3.5-2B-Q4_K_M.gguf`, **1 396 198 496 octets** (1,40 Go sur la table HF) |
| Provenance des poids | URLSession vers HF pour le LLM ; `DownloadUtils` / `PocketTtsResourceDownloader` pour STT et TTS | Documents ou bundle uniquement. Écran d’accueil sans barre de téléchargement |
| Contexte | `n_ctx` 2048 | `n_ctx` 8192 |
| Cache KV | F16 par défaut | `type_k` et `type_v` = `GGML_TYPE_Q8_0`, Flash Attention forcée |
| Partage de fichiers | absent | `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace` |
| Signature | team et bundle de l’upstream (`com.fikrikarim.volocal`) | `DEVELOPMENT_TEAM` `CDMG5NRWRF`, bundle `com.pointbarre.volocal` |

Non touché : `SharedAudioEngine` (AVAudioEngine, AEC Voice Processing), le barge-in, les callbacks EOU, `speak` / `stop` de PocketTTS, le buffer de phrases. `VoicePipeline.configure` refuse seulement de passer `isReady` si un modèle n’a pas pu être chargé, pour laisser le message à l’écran.

## Pièges

**Contention GPU mlx-audio.** Le TTS est d’abord passé par mlx-audio-swift (Metal). Le LLM occupe déjà le GPU : coupures et blocages en streaming. Moonshine (ONNX, GPU/CPU) ajoutait la même pression côté STT. Le passage à FluidAudio CoreML (Parakeet sur l’ANE, PocketTTS en CPU+GPU, parce que l’ANE en float16 abîme le décodeur Mimi) est le contournement retenu. Ne pas réintroduire MLX sur le chemin audio.

**Mémoire / jetsam avec `n_ctx` 8192.** Qwen3.5-2B a 24 couches dont 6 seulement sont en attention pleine (1 sur 4), 2 têtes KV, `head_dim` 256. Le cache K+V Q8_0 de ces 6 couches à 8192 tokens est de l’ordre de quelques dizaines de Mo, pas de plusieurs Go. Le risque jetsam vient du reste : GGUF d’1,40 Go résident sur le GPU (`n_gpu_layers = 99`), les scratch Metal qui grandissent avec `n_ctx` et `n_batch` 512 au prefill, plus Parakeet et PocketTTS déjà en mémoire. L’upstream mesurait ~1,2 Go à `n_ctx` 2048 et citait un plafond d’environ 3 Go sur iPhone 15. Si le processus meurt au `llama_init_from_model` (jetsam, `memorystatus`), baisser `ModelRegistry.llmContextSize` avant de toucher à l’audio.

**Flash Attention + V en Q8_0.** llama.cpp refuse un cache V quantifié sans Flash Attention (`quantized V cache was requested, but this requires Flash Attention`). `LLAMA_FLASH_ATTN_TYPE_AUTO` peut encore la couper. Le contexte est donc créé avec `flash_attn_type = LLAMA_FLASH_ATTN_TYPE_ENABLED`. Équivalent CLI : `--cache-type-k q8_0 --cache-type-v q8_0 --flash-attn on`. Il faut un llama.swift 2.x qui réexporte le `llama.h` actuel (`type_k`, `type_v`, `flash_attn_type`). Ce dépôt n’a pas été compilé : si le XCFramework résolu est plus ancien et n’a qu’un booléen `flash_attn`, le build cassera sur ces trois champs. Un cache Q8_0 sur CPU + KleidiAI a déjà produit du charabia sur d’autres appareils ; ici toutes les couches partent sur Metal, mais une sortie illisible au premier prompt doit faire suspecter le couple FA + V Q8_0 avant le tokenizer.

**Téléchargement caché dans FluidAudio.** `PocketTtsManager.initialize()` et `ensureVoice` téléchargent si un fichier manque. L’app ne les appelle que lorsque les sentinelles sont déjà là. Ne pas « simplifier » en rappelant `initialize()` sur un dossier incomplet.

**Mauvais layout.** `models` ≠ `Models`. `320ms/` à la racine de Documents n’est pas trouvé. `v2/en/` de PocketTTS non plus. Un GGUF au bon nom mais d’une autre taille (y compris l’ancien Q4_K_S) est refusé : l’écran indique la taille lue et les 1 396 198 496 octets attendus.

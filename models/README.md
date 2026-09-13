# Your local model library

Archii Vault includes a native MLX runtime on Mac, iPhone, and iPad. Installed models run directly on that device without an account, hosted API, separate Python environment, or internet connection.

## Install a starter in the app

Open **Settings → Models & chat** and choose either model:

| Choice | Checkpoint | Download | Format |
| --- | --- | --- | --- |
| Smaller Qwen | Qwen 3.5 2B | 1.75 GB | MLX, 4-bit, safetensors |
| Larger Qwen | Qwen 3.5 4B | 3.06 GB | MLX, 4-bit, safetensors |

The Mac **Starter** edition already includes the smaller model. The lightweight Mac app and iOS source builds download models when you explicitly choose Install. The larger model is available in Settings rather than embedded in the source repository. Downloading both needs about 4.81 GB of storage, plus temporary setup headroom. Running them needs additional RAM; the app checks current memory before loading.

Downloads come directly from the pinned Hugging Face model revisions in [starter-models.json](starter-models.json). Every file has a byte count and SHA-256 checksum. A partial download is hidden from the model chooser until all files validate; pause and resume without losing finished files. Keep the app open while downloading on iPhone/iPad. If iOS suspends the app, reopen it and choose Install/Resume again. A retry reuses verified files and partial bytes.

Select the model after installation. In chat, **On this device** means local inference and offline availability. **Paired Mac** means the model runs on the Mac and needs a connection. Weights do not travel through document sync.

## Completely local import

Get a **complete compatible MLX model folder**. Keep `config.json`, `tokenizer.json`, `tokenizer_config.json`, the chat template, and **every** `.safetensors` shard together. Do not import a single weight file. Zip archives must be unzipped first.

- **Mac:** Settings → Models & chat → Import model folder; choose it in Finder. Vault copies it into its own library.
- **iPhone/iPad:** Transfer the folder with an external drive, Finder File Sharing, or AirDrop (zip the folder, then unzip in Files). Choose Import model folder and select the folder in Files. Vault copies it onto that device.
- **Direct copy:** Open the Models folder from Settings, place complete model subfolders inside it, then Refresh. On mobile this is **On My iPhone/iPad → Archii Vault → Models**.

The copy is independent of the source folder, so disconnecting the drive afterward does not remove the installed model. Duplicate imports do not overwrite an installed model. Incomplete/unsupported models show a useful error. A `.disabled` marker inside a model folder hides it without deleting weights.

## Optional command-line setup

Python 3.10+ is needed only for this helper, not for the app:

```sh
# Install both into the Mac app's local model library:
python3 scripts/download-model.py all --app

# Prepare portable folders on another drive:
python3 scripts/download-model.py all --destination /path/to/Models

# Inspect sources and sizes without downloading:
python3 scripts/download-model.py all --dry-run
```

Use `qwen-small` or `qwen-large` instead of `all` for one model. Repeat the command to resume interrupted work. The helper validates checksums, keeps attribution beside the weights, and preserves existing installed folders.

For a developer build, download into the repository's ignored `models/` directory, build the Mac app, and launch its executable with an explicit library:

```sh
python3 scripts/download-model.py all
VAULT_MODELS_DIR="$PWD/models" 'dist/Archii Vault.app/Contents/MacOS/Archii Vault'
```

For an iOS build, choose your own Xcode signing team, install the app, then use the in-app downloader or Files import. No model paths, device identifiers, or signing teams need to be edited into source. The same model folder can be installed independently on multiple devices you own.

## Other checkpoints and limits

Supported architecture names include `llama`, `qwen2`, `qwen3`, `qwen3_5`, `qwen3_5_text`, `gemma`, `gemma2`, `gemma3_text`, `gemma4`, `gemma4_text`, `gemma4_unified`, `mistral`, `phi3`, and `smollm3`. This is an architecture allowlist, not a guarantee that every variant loads or fits memory. GGUF, Ollama, and LM Studio adapters are future work.

An optional `vault-model.json` can supply a friendly `name`, `precision`, and `recommended: true`. Executable model code is never imported. Chat uses text and local source excerpts; an upstream model's advertised image/audio/video capabilities are not automatically exposed by Vault.

Mobile currently uses up to 4K context and 1K output; Mac uses up to 16K context and 4K output, bounded by model metadata. Models load on demand and unload after an answer. Cancellation, backgrounding on iOS, and low-memory checks preserve the saved conversation. Only one Vault model session uses the local runtime at a time, including requests from paired devices.

## Model licenses and provenance

Both starter checkpoints are Apache-2.0. Original licenses and conversion attribution are preserved in [Qwen-LICENSE.txt](Qwen-LICENSE.txt) and [Qwen-NOTICE.txt](Qwen-NOTICE.txt), and copied into installed model folders. These licenses are independent of the application's license.

- [2B original](https://huggingface.co/Qwen/Qwen3.5-2B) · [MLX conversion](https://huggingface.co/mlx-community/Qwen3.5-2B-4bit)
- [4B original](https://huggingface.co/Qwen/Qwen3.5-4B) · [MLX conversion](https://huggingface.co/mlx-community/Qwen3.5-4B-4bit)

The pinned manifest records original and converted revisions, original-license hashes, exact file sizes, and file hashes. Model weights are excluded from Git and ordinary vault sync. See [validation notes](../docs/VALIDATION.md) for the scope of actual device checks; a successful example is not a broad accuracy benchmark.

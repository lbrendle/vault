# 0.5.0-beta.1

Vault is a private document workspace for Mac, iPhone, and iPad. Ordinary folders remain the source of truth; local search, progressive readers, direct device sync, and native local AI keep the workspace close to your files.

## Downloads

- **Vault-0.5.0-beta.1-macOS-arm64.zip**: the lightweight Mac app. Install either Qwen starter in Settings → Models & chat.
- **Vault-0.5.0-beta.1-Mac-Starter.zip**: the same app with the pinned Qwen 3.5 2B 4-bit model included. Unzip, move Vault.app to Applications, choose a folder, and start a local conversation. Qwen 4B is available as an optional download.
- **SHA256SUMS.txt**: checksums of release assets.
- **vault-demo-1080p.mp4** and **vault-social-28s.mp4**: product videos using a fictional library.

Mac downloads require Apple silicon and macOS 14 or later. These bundles are Developer ID signed **but not notarized**; macOS may display a security warning or block opening. This beta has no automatic updater. Download releases only from this repository.

iPhone/iPad distribution is source-based: build with Xcode and your own signing team. There is no generally installable public IPA, App Store release, or TestFlight invitation. See [BUILDING.md](BUILDING.md) and [the model guide](../models/README.md).

## Included

- Progressive Markdown and continuous, virtualized PDF reading.
- Linked documents, local search, graph exploration, tabs, properties, and recovery copies.
- Twenty-four palettes with light and dark variants.
- Native local MLX inference, two pinned Qwen starters, and model-folder import.
- Authenticated direct device sync, changed-file transfer, resumable binary files, and shared conversation state.
- Fixes for workspace-switch races, tags and citations, sidebar page refreshes, and iPhone swipe-versus-tap handling.

## Current limits

Keep Vault open on both devices during initial sync. Large libraries take time to transfer and index; iOS can suspend background work. Internet relay sync, guaranteed background sync, GGUF, Ollama/LM Studio connections, and third-party plugin execution are not included. See [COMPATIBILITY.md](COMPATIBILITY.md).

Model quality and memory needs vary. The 4B checkpoint passed a small native evidence-and-arithmetic smoke check on Mac and iPhone; the smaller 2B model made an arithmetic error with thinking disabled. Verify model claims against your sources. See [VALIDATION.md](VALIDATION.md).

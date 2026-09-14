# 0.5.0-beta.3 · Lab inside Vault

Enable **Settings → Lab → Enable Lab** to work with Python and Jupyter notebooks inside the existing Vault app. Lab is optional; your folders, Markdown reader, links, and device sync stay part of the same workspace.

## In this release

- Python and notebook discovery in selected vault folders, including older saved file rules; filenames and wikilinks open local files in place.
- Local iPhone/iPad Python, scientific libraries, plots, variables, tests, Git tools, and explicit MLX/Metal GPU bridges.
- A searchable folder tree with separate run history, expandable Console/Variables/Packages panels, and a full-width assistant on phones.
- Notebook `%pip` and `!pip` installs, project caches, bounded download retries, and concise errors with expandable details.
- Notebook access to installed Vault models, plus optional Codex and Claude Code adapters using an existing Mac CLI login.

## Downloads and updates

**Mac:** choose the smaller Apple-silicon app download or Mac Starter with the pinned, licensed Qwen 3.5 2B model. macOS 14 or later is required. Both bundles are Developer ID signed and are not notarized. For Lab, prepare a local Python environment using [the build guide](BUILDING.md); remote hosting is optional.

**iPhone/iPad:** one universal build, **0.5.0 (28)**, uses the original Vault app identifier. Install updates over Vault to preserve local files and models. [TestFlight invitation](https://testflight.apple.com/join/2G2ngjAk). GitHub publication and successful uploads do not imply Apple beta-review approval. Current upload, processing, and review status are recorded on the [GitHub release](https://github.com/lbrendle/vault/releases/tag/v0.5.0-beta.3).

## Validation and limits

43 web tests, 37 Swift core tests, and 17 Python tests pass. Native builds and Simulator layout checks cover both phone and tablet layouts. Earlier physical-device checks exercised scientific notebooks, original-file saves, GPU calls, package installation, and installed local models. See [validation scope](VALIDATION.md) for the exact boundaries.

Current Codex/Claude Code npm distributions have no iOS target; a working on-device port is not included. Optional paired-Mac Lab execution over LAN/Tailscale still needs a passing physical-device acceptance check. The iOS console is an embedded Python/tool console, and does not provide arbitrary Unix subprocesses or every native scientific package. [Lab capabilities and setup](LAB.md).

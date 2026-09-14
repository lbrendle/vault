# Vault on iPhone and iPad

[Join the Vault TestFlight beta](https://testflight.apple.com/join/2G2ngjAk).

The Lab release is **0.5.0 (29)**. Check the [release notes](https://github.com/lbrendle/vault/releases/tag/v0.5.0-beta.3) for its upload and processing status. The first public beta, build 26, was still awaiting Apple review when this release was prepared. Apple permits only one build of a version in beta review at a time. An upload or GitHub release does not establish public TestFlight availability; the invitation accepts installations after Apple approves a build.

Lab is optional in **Settings → Lab**. It provides local Python and Jupyter notebook editing/execution, with a file tree, expandable development panels, and installed local models. See [Lab capabilities](LAB.md) for supported libraries and optional Mac assistants.

## Install

1. Open the invitation on your iPhone or iPad.
2. Install Apple's TestFlight app if prompted.
3. Accept the invitation and install **Vault: Documents & Local AI**. The app appears on your Home Screen as **Vault**.
4. Create a local vault, or choose a folder you want to use.

One universal app supports both iPhone and iPad on iOS/iPadOS 17 or later. Read, edit, and search documents without installing a model. Mac users should use the native Mac download linked from the [release page](https://github.com/lbrendle/vault/releases).

## Local models

Open **Settings → Models & chat**, then choose **Install smaller Qwen** or **Install larger Qwen**. The smaller Qwen 3.5 2B model is about 1.75 GB; the larger 4B model is about 3.06 GB. Downloads are optional and require internet access once. After installation, on-device conversations work offline.

The TestFlight app does not bundle multi-gigabyte weights. Both starter models are supplied through the built-in installer, with pinned revisions, resumable downloads, SHA-256 verification, and their licenses. You can also import a complete supported MLX model folder from Files, a USB drive, or AirDrop. See the [model guide](../models/README.md).

Model storage size is not its working-memory requirement. Vault checks the memory available to the app before inference; a device that can run Vault may not have enough memory for every model. Documents remain usable without loading a model.

## Bring your documents across

Use **Settings → Device sync** to pair your existing Mac vault with a local vault on the phone or tablet. Keep Vault open on both devices during the initial transfer. Synced documents are stored locally and remain readable offline. Changes, including shared conversation state, synchronize in both directions when paired devices reconnect. See [sync details and conflict handling](SYNC.md).

If Vault is already installed from Xcode under this project's original signing team, install the TestFlight update over it. Do not delete the existing app to update: deleting the app can remove its local documents and models. Keep a separate copy of important files before changing installation methods.

## Beta feedback

Use TestFlight feedback or [GitHub issues](https://github.com/lbrendle/vault/issues). Use fictional examples when reporting document problems; never attach a private vault, conversations, pairing codes, or credentials to a public issue. See the [privacy policy](PRIVACY.md).

For a build without TestFlight, follow [BUILDING.md](BUILDING.md) with your own Xcode signing team. A GitHub source download is not a directly installable iOS app.

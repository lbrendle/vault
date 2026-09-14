# Vault privacy

Effective September 13, 2026.

Vault is an open-source document workspace. The app has no Vault account, analytics endpoint, advertising SDK, hosted document storage, or hosted inference service. The project maintainers do not receive your documents, searches, conversations, or model prompts through the app.

## Files and conversations

Documents remain in the folder you choose. Vault stores indexes, preferences, recovery copies, and conversation state locally. When you pair devices, Vault transfers documents and shared workspace state directly between those devices over an authenticated, encrypted connection. Local model inference runs on your device, or on a paired device when you select that option.

Your operating system and any storage provider you independently choose may back up or synchronize app data under their own settings and policies. Removing a workspace from the app is not a request to erase the underlying documents. Manage or delete those files with Finder or Files, and manage backups separately.

## Network connections

Installing a starter model downloads files from Hugging Face and its download infrastructure. Those services receive the network information needed to serve a download, such as your IP address. Vault does not send your research or conversations with model downloads. You can instead import a complete supported model folder and use it offline.

Device sync and paired model access contact devices you pair. External links open in your browser and are governed by the destination's privacy policy. Remote media embedded in documents is blocked by default.

## Optional Lab and coding assistants

Lab runs Python and installed Vault models locally by default. User-written code can itself make network requests. Selecting a paired Mac routes the requested computation through the authenticated vault connection over LAN or Tailscale. Tailscale, when independently installed, operates under its own service and network policies.

Codex and Claude Code are optional Mac CLI integrations. Running one can transmit your prompt and project context to that provider and use your existing account quota. Authentication stays in the CLI’s own local credential storage; Vault does not copy it into documents or sync it. Assistant prompts and results are saved as local project run records and can sync to your paired devices. Reading documents, ordinary local Python execution, and calls to Vault’s installed models do not invoke either provider.

## Diagnostics and support

Vault stores limited local diagnostics for troubleshooting; it does not automatically send them to the maintainers. Apple may collect platform diagnostics and TestFlight feedback according to your Apple settings and Apple's policies. If you submit feedback or a GitHub issue, the information you choose to include is received by that service and the maintainers. Public GitHub issues are public: do not attach private documents, conversations, pairing codes, or credentials.

## Apple privacy declarations

The bundled privacy manifest declares no tracking or data collection by the app developer. Required-reason API access is limited to app preferences, metadata of app files and files you explicitly select, and available storage checks before downloads and file transfers. These APIs are not used to fingerprint users or devices.

Vault uses Apple's Network, Security, CryptoKit, and URLSession APIs for transport security and file integrity; it does not implement a proprietary encryption algorithm. The iOS export declaration reflects this use of operating-system cryptography.

## Contact and changes

For questions about this policy, open an issue at [github.com/lbrendle/vault](https://github.com/lbrendle/vault/issues) without including private information. See [SECURITY.md](../SECURITY.md) for reporting a security vulnerability. Changes to this policy are recorded in the repository history.

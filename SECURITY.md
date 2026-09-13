# Security

Only the latest public beta receives fixes. This project has not undergone an independent security audit.

Please report suspected vulnerabilities through [GitHub private vulnerability reporting](https://github.com/lbrendle/vault/security/advisories/new). Do not include personal notes, model prompts, pairing secrets, credentials, or device profiles. Provide a minimal synthetic reproduction, affected version, impact, and suggested mitigation when possible.

The app handles untrusted documents, model metadata, and peer transfers. Useful review areas include path traversal and symlinks, WebKit bridge boundaries, Markdown sanitization, content security policy, PDF resource/range loading, atomic file updates, conflict preservation, peer authentication, bounded memory, and checksum verification.

A pairing code grants access to the paired vault; share it only with devices you trust. Local storage follows your operating system's file protection and backup settings. Vault does not add independent encryption at rest to an ordinary desktop folder. Imported models must be from a publisher you trust and contain a compatible configuration, tokenizer, and complete safetensors weights.

Public release downloads are separate from developer provisioning. We never ask contributors to upload signing keys or personal research data. Download weights only through the pinned starter catalog or your own explicitly selected local folder.

# Architecture

The Apple app shell hosts a local React interface in WKWebView. A narrow message bridge exposes file, search, sync, preview, and model operations. The `vault:` URL scheme serves local application/document resources without an HTTP server. Document rendering uses sanitization and a restrictive content security policy.

`VaultCore` owns ordinary-file access, exclusion rules, SQLite indexing, link metadata, revision recovery, model-folder inspection, checksum-verified starter installation, and peer transport/catalog logic. Database/index files are local support data; they do not replace the source documents. Changes are written atomically and checked against the version read where applicable.

`VaultApp` owns platform integration: folder permissions, filesystem watching, device discovery, window/keyboard behavior, native previews, theme-aware app icons, and native MLX inference. Mac and mobile share `LocalModel.swift`; only platform memory/background handling differs. A tokenizer loader reads the selected folder directly. No Hugging Face cache path, personal Python install, unrelated process inspection, or research-specific lock is involved. A process-local admission lock prevents simultaneous Vault model sessions.

The interface keeps expensive Markdown and graph work off the main thread where practical. Long Markdown renders progressively, PDFs request local byte ranges and virtualize pages, and graph rendering chooses appropriate levels of detail without excluding documents from the indexed graph.

Device sync has its own journal and content fingerprints. Bonjour discovers peers; authenticated encrypted transport exchanges manifests and file chunks, preserving concurrent edits as conflicts and resuming interrupted copies. Saved conversation/bookmark state shares the vault's synchronization path. Device UI preferences and model weights stay local.

Starter downloads use ephemeral URLSession requests to pinned HTTPS resources, with streaming writes, range resume, expected-length checks, SHA-256 validation, staging, and final folder validation before atomic installation. The Python helper implements the same manifest format for offline provisioning. Download cancellation retains partial bytes; it never replaces a currently installed model.

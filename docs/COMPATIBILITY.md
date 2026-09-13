# Compatibility and limits

Archii Vault is an independent application using ordinary files. This beta does not claim exact Obsidian parity.

| Area | Available | Current limits |
| --- | --- | --- |
| Markdown | Source editing, reading and split modes; wiki links, backlinks, tags, callouts, footnotes, math, Mermaid | No Obsidian Live Preview/WYSIWYG parity; plugin syntax can differ |
| Organization | Folders, tabs, bookmarks, daily notes, templates, frontmatter | No arbitrary workspace split parity or community plugins |
| Canvas / Bases | Common file formats and a useful subset of views/editing | Not every Canvas gesture, formula, filter, or Base layout |
| Documents | Continuous local PDF reader, attachments, supported platform previews | No complete PDF/Office full-text extraction or OCR index |
| Large text | Progressive long-document rendering and worker parsing | Editing has a 64 MiB text limit; exceptionally large files remain costly |
| Graph | Full indexed library, pan/zoom, search, adaptive clusters and labels | Layout changes with scale; huge graphs do not draw every label at once |
| Search | Local SQLite full-text search for indexed text, document titles and paths | The initial index needs time; not every attachment's contents are searchable |
| Sync | Bidirectional direct peer sync, offline copies, resumable transfer, conflict preservation | Same local network; iOS foreground needed for dependable progress; no hosted relay |
| AI | Native MLX text chat; two pinned Qwen starters; validated local folder import | No GGUF or local-server adapters yet; imported architecture support is not a blanket checkpoint guarantee |
| AI modalities | Text with retrieved local document excerpts | Vision/audio/video capabilities of an upstream checkpoint are not exposed just because its weights are present |
| Platforms | Apple silicon Mac, iPhone, iPad | No Windows, Linux, or Android application; no App Store/TestFlight distribution in this beta |

No speed or model-fit promise applies to every device. Local AI consumes additional working memory beyond weight storage. The app rejects a load or stops generation if current memory is insufficient. Context/output budgets are bounded and disclosed in settings; mobile currently uses up to 4K context and 1K output, desktop up to 16K context and 4K output, within model metadata and memory availability.

Themes and model selection are local preferences. Saved conversations and bookmarks sync, but unsaved drafts and model weights do not. Sync is not a substitute for an independent backup. See [SYNC.md](SYNC.md).

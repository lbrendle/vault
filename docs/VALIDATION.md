# Validation scope

Public-beta validation is tracked here after the corresponding checks complete. Automated tests use temporary, synthetic documents and model fixtures. Device smoke tests use a fictional evidence question and do not read a research vault.

The initial release includes automated coverage for document indexing and edits, path/symlink boundaries, binary/range access, long documents, shared conversation state, synchronization conflicts/resume behavior, model-folder validation, and starter download corruption/range handling. Web checks cover parsing, graph geometry/labels, model selection, styles, and shared state.

The Qwen 3.5 4B checkpoint completed a native local text-generation smoke test on iPhone 17 Pro and iPad Pro M5 during pre-release development. This establishes that the integration can execute on those devices; it is not a general benchmark or a claim that every device can fit that model. See the release notes for checks performed against the exact published revision.

A compile is not a physical-device inference result. Local execution is not the same as a separately observed radios-off test. Full Obsidian parity, universal hardware support, independent security auditing, App Store approval, and seamless iOS background networking are not claimed.

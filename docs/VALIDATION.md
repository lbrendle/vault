# Validation scope

Public-beta validation is tracked here after the corresponding checks complete. Automated tests use temporary, synthetic documents and model fixtures. Device smoke tests use a fictional evidence question and do not read a research vault.

The initial release includes automated coverage for document indexing and edits, path/symlink boundaries, binary/range access, long documents, shared conversation state, synchronization conflicts/resume behavior, model-folder validation, and starter download corruption/range handling. Web checks cover parsing, graph geometry/labels, model selection, styles, and shared state.

The Qwen 3.5 4B checkpoint completed a native local text-generation smoke test on iPhone 17 Pro and iPad Pro M5 during pre-release development. This establishes that the integration can execute on those devices; it is not a general benchmark or a claim that every device can fit that model. See the release notes for checks performed against the exact published revision.

A compile is not a physical-device inference result. Local execution is not the same as a separately observed radios-off test. Complete format and workflow coverage, universal hardware support, independent security auditing, App Store approval, and seamless iOS background networking are not claimed.

## Starter model quality

Native 4B inference passed a small fictional evidence-and-arithmetic check on an iPhone 17 Pro and an Apple silicon Mac. The 2B model completed generation but gave an incorrect percentage difference with thinking disabled. Treat the smaller model as a lightweight drafting companion; verify calculations and factual claims against the sources. These checks are integration smoke tests, not general model benchmarks.

## Reader and connectivity regressions

Tests cover tag-array display/edit round trips, chat citations wrapped in inline code, document links containing spaces, and simultaneous connection attempts when one local route stalls. Sync preserves its authenticated transport on every route. Returning to the foreground refreshes local discovery; diagnostics stored locally omit pairing keys, document content, and device identifiers.

## Beta 1 regression checks

The release candidate passed 29 Swift core tests, 34 web tests, and 3 starter-download tests. Both native app targets compiled in Release configuration. The Mac bundle has a Developer ID signature; it is not notarized.

The sync regression sends slash-heavy binary attachments through the real authenticated loopback transport, resumes a partial transfer, and verifies documents and conversation data in both directions. This guards against base64 JSON expansion exceeding the frame limit. It does not claim a completed first transfer for every large physical-device library.

Workspace tests reject stale responses after a folder or workspace change and retain already loaded file pages while sync updates arrive. iPhone gesture tests cover a swipe with no intermediate move events, ordinary taps, cancellation, and scroll bounds. Repeated swipes and a separate deliberate tap were checked in the native iPhone simulator. Build 25 was installed on a physical iPhone 17 Pro; finger scrolling without selecting or opening rows was confirmed on that device. The iPhone-only handler leaves iPad, mouse, and keyboard navigation on their native paths.

The demonstration includes a real native Qwen 3.5 4B response on Mac and opening its rendered document citation. The example library is fictional. Mobile footage uses Apple’s Simulator; it is not evidence of physical-device inference speed or of an offline-radio test.

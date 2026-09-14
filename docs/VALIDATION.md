# Validation scope

Public-beta validation is tracked here after the corresponding checks complete. Automated tests use temporary, synthetic documents and model fixtures. Device smoke tests use a fictional evidence question and do not read a research vault.

The initial release includes automated coverage for document indexing and edits, path/symlink boundaries, binary/range access, long documents, shared conversation state, synchronization conflicts/resume behavior, model-folder validation, and starter download corruption/range handling. Web checks cover parsing, graph geometry/labels, model selection, styles, and shared state.

The Qwen 3.5 4B checkpoint completed a native local text-generation smoke test on iPhone 17 Pro and iPad Pro M5 during pre-release development. This establishes that the integration can execute on those devices; it is not a general benchmark or a claim that every device can fit that model. See the release notes for checks performed against the exact published revision.

A compile is not a physical-device inference result. Local execution is not the same as a separately observed radios-off test. Complete format and workflow coverage, universal hardware support, independent security auditing, App Store approval, and seamless iOS background networking are not claimed.

## Optional Lab development candidate — September 13, 2026

This entry describes the Lab development branch, not the published build 27 beta.

- 38 web tests, 32 Swift core tests, and 6 Python script tests passed. Regression coverage includes original-folder saves, stale-write rejection, path/symlink boundaries, explicit code extensions, notebook Markdown links/backlinks, and Jupyter metadata round trips.
- The existing Mac and iPhone/iPad app targets built in Release configuration. The iPhone Simulator target also built. Shipping bundle identifiers remain unchanged; separate identifiers were used for development installs.
- Three native tests passed on a physical iPad Pro M5: original-file execution/editing, file/session/error handling, and the scientific/GPU examples. The four bundled notebooks executed with Python socket connections disabled. This verifies those examples without a network dependency, not an operating-system radios-off test.
- Native iPad checks exercised NumPy, pandas, Matplotlib plots, SymPy, NetworkX, SQLite, pytest, local Git, UTF-8 save/reopen, MLX gradients and checkpoint reload, and an editable Metal kernel compared with a NumPy result. A separate test installed and imported a pure Python wheel.
- A physical iPad UI test enabled Lab, opened a Python file through an ordinary note link, ran it in its original folder, opened a notebook through a wikilink, ran and saved its output, followed its Markdown link back to the guide, disabled Lab, and verified that it remained hidden after relaunch. An earlier physical test covered editing Python with the software keyboard and running the saved file after relaunch.
- The same link, execution, toggle, and relaunch flow passed in the iPhone 17 Pro Simulator. Screenshot review verified the phone's two-row toolbar and accessible footer controls after correcting overlapping labels.
- Mac UI checks followed note links into the original Python file and notebook, executed both through the local Python process, generated a Matplotlib plot, and followed the notebook link back to the guide. A separate Mac worker check passed SciPy, scikit-learn, real subprocess execution, and pytest.
- Mac setup recovered from a missing Python executable through the app's host settings, with remote hosting disabled.

The physical iPhone was unavailable during Lab validation. Simulator evidence does not establish physical iPhone GPU behavior. The paired-Mac LAN acceptance test did not pass; that path remains unverified. Full PyTorch/MLX Python APIs, arbitrary native iOS wheels, subprocess isolation on iOS, and complete advanced scientific-curriculum compatibility are not claimed. See [Lab capabilities](LAB.md).

## Starter model quality

Native 4B inference passed a small fictional evidence-and-arithmetic check on an iPhone 17 Pro and an Apple silicon Mac. The 2B model completed generation but gave an incorrect percentage difference with thinking disabled. Treat the smaller model as a lightweight drafting companion; verify calculations and factual claims against the sources. These checks are integration smoke tests, not general model benchmarks.

## Reader and connectivity regressions

Tests cover tag-array display/edit round trips, chat citations wrapped in inline code, document links containing spaces, and simultaneous connection attempts when one local route stalls. Sync preserves its authenticated transport on every route. Returning to the foreground refreshes local discovery; diagnostics stored locally omit pairing keys, document content, and device identifiers.

## Beta 1 regression checks

The release candidate passed 29 Swift core tests, 34 web tests, and 3 starter-download tests. Both native app targets compiled in Release configuration. The Mac bundle has a Developer ID signature; it is not notarized.

The sync regression sends slash-heavy binary attachments through the real authenticated loopback transport, resumes a partial transfer, and verifies documents and conversation data in both directions. This guards against base64 JSON expansion exceeding the frame limit. It does not claim a completed first transfer for every large physical-device library.

Workspace tests reject stale responses after a folder or workspace change and retain already loaded file pages while sync updates arrive. iPhone gesture tests cover a swipe with no intermediate move events, ordinary taps, cancellation, and scroll bounds. Repeated swipes and a separate deliberate tap were checked in the native iPhone simulator. Build 25 was installed on a physical iPhone 17 Pro; finger scrolling without selecting or opening rows was confirmed on that device. The iPhone-only handler leaves iPad, mouse, and keyboard navigation on their native paths.

The demonstration includes a real native Qwen 3.5 4B response on Mac and opening its rendered document citation. The example library is fictional. Mobile footage uses Apple’s Simulator; it is not evidence of physical-device inference speed or of an offline-radio test.

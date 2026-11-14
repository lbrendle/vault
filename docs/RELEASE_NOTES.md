# Unreleased · iPhone Duo and reliability

Changes on the way to the next build. Version, build number and download details are added when it ships; [validation scope](VALIDATION.md) records what has and has not been checked.

## iPhone Duo

- Built with Xcode 27.2 or newer, Vault fills both displays. The outer display shows one pane at a time and keeps clear of the system's side column; the inner display shows the sidebar beside the page.
- Opening, closing or turning the phone keeps the page you were on. The sidebar steps aside when the window narrows and returns when it widens. The same applies to rotating any iPhone and to resizing an iPad window.
- Partly folded and held upright, the sidebar takes the left page and the document the right, and split preview puts source and preview on a page each. The turned (tabletop) posture has no layout of its own yet.

## Fixes

- Heading links in long documents hold their destination while the sections above finish loading.
- Ticking a checkbox in reading view edits that task's own line. Previously a fenced example, a numbered task or a quoted task above it could shift the edit to a different line.
- Editing one property no longer rewrites the others: `id: 007`, `version: 1.10`, long numbers, quoting, order and comments are kept as written.
- A document that cannot be saved because its file changed elsewhere no longer traps you on it. **Reload from disk** discards the draft, and **Save a copy** keeps the draft in a new note and leaves the original as it is on disk.
- Text that matches the saved file is no longer kept as a draft, so an old copy cannot reappear over newer changes.
- Document commands appear only where they apply. Add property, Insert template and Save are no longer offered for PDFs and images or when no document is open, which could leave an attachment unsavable or bring up the error screen. Print is no longer offered for notes on iPhone and iPad, where it did nothing.
- A canvas whose JSON becomes invalid while editing, or switching between a valid and an invalid canvas, shows the repair message instead of the error screen.
- Settings: the excluded-folder lists accept new lines and spaces as you type and are tidied when applied; the daily-notes and templates folder fields can be cleared and retyped.
- Keyboard: Control shortcuts are left to text editing (Control-E, Control-K, Control-N and the rest no longer trigger app commands). Escape closes dialogs, and Return runs the first match in the command palette and quick switcher.
- Chat on the software keyboard: Return starts a new line and the arrow sends. A hardware keyboard's Return still sends.
- Dialogs, the error banner and icon-only buttons are labelled for VoiceOver; small close and dismiss buttons have a finger-sized hit area on touch screens.
- Home's recently changed list, search results, the quick switcher and the template picker each keep their own list. Opening a picker no longer changes what Home shows, and the choices for a link with several possible targets stay on screen.
- In a long note, ticking a task or editing beside the preview keeps the reader where it was instead of jumping toward the top. The preview follows typing after a short pause, and a change to the note no longer jumps back to the last heading you navigated to.
- Typing saves the workspace state every two seconds at most, not twice a second, and a Lab notebook left open on another page no longer re-renders with each keystroke.
- A conversation merged from another device appears in full without reloading the workspace.
- iPhone and iPad: Vault no longer changes its app icon, and so triggers the system's alert, on first launch. The icon follows the theme once an appearance has been chosen.

## Sync and files

- Vault never re-creates a vault folder that has gone missing. Previously, renaming or moving the folder while the app was open could leave an empty folder at the old path, which sync then read as every document having been deleted and passed on to paired devices. Writes now fail with a message to reopen the folder.
- Two devices that hold different versions of a document under identical sync history now keep both as a conflict instead of each treating its own copy as current.
- A conversation continued on one device and renamed or archived on another keeps all of its messages when the two sync.
- PDFs, images and other attachments can be moved to trash and renamed or moved; links to a moved attachment are updated. A note cannot be renamed into an attachment extension, or the reverse.
- Only Vault's own interface can call into the app. A vault HTML file can no longer be opened as a page inside the app window, and is served as plain text.
- On Mac, renaming, moving or deleting a folder in Finder updates search, links and the sidebar without a relaunch, and sync restarts after the Mac wakes.
- A malformed transfer offset from a paired device is rejected instead of stopping the app.
- Saving a note keeps its Finder tags, other extended attributes and creation date, and so does a synced version replacing a file. A locked file is still saved, without them.
- Sync history now belongs to the sync catalog. If the catalog is lost, for example after the cache is cleared or the vault folder is renamed, documents that differ between devices are kept side by side as conflicts; previously an older copy from another device could replace a newer one.
- One document no longer stops the rest of a sync pass, in either direction. A document this device cannot receive (not enough space, a failed checksum, a path it has to refuse), one the other device declines for the same reasons, or one that changed here before it could be sent is put off and offered again on a later pass. Everything else is still received and sent, and the problem is reported, with the document's name when sending, once the pass ends.
- A text file over the 64 MiB editor limit is listed by name and synced, and no longer keeps the index from clearing documents that were deleted or renamed.
- Recovery keeps the newest 100 saved versions of each document, the number the recovery list shows, and removes older ones as new versions are saved. Interrupted transfer files untouched for a week are removed.

# 0.5.0-beta.3 · Lab inside Vault

Enable **Settings → Lab → Enable Lab** to work with Python and Jupyter notebooks inside the existing Vault app. Lab is optional; your folders, Markdown reader, links, and device sync stay part of the same workspace.

## In this release

- Python and notebook discovery in selected vault folders, including older saved file rules; filenames and wikilinks open local files in place.
- Local iPhone/iPad Python, scientific libraries, plots, variables, tests, Git tools, and explicit MLX/Metal GPU bridges.
- A searchable folder tree with separate run history, expandable Console/Variables/Packages panels, and a full-width assistant on phones.
- Notebook `%pip` and `!pip` installs, project caches, bounded download retries, and concise errors with expandable details.
- Notebook access to installed Vault models, plus optional Codex and Claude Code adapters using an existing Mac CLI login.

## Downloads and updates

**Mac:** choose the smaller Apple-silicon app download or Mac Starter with the pinned, licensed Qwen 3.5 2B model. macOS 14 or later is required. Both bundles are Developer ID signed under lauren brendle, notarized by Apple, and include stapled tickets. Gatekeeper accepted both packages on September 15, 2026. For Lab, prepare a local Python environment using [the build guide](BUILDING.md); remote hosting is optional.

**iPhone/iPad:** one universal build, **0.5.0 (30)**, uses the original Vault app identifier. Install updates over Vault to preserve local files and models. [Join the public TestFlight beta](https://testflight.apple.com/join/2G2ngjAk). Apple has approved build 30 for external beta testing, and the public invitation was verified on September 15, 2026. App Store publication is a separate release step.

## Validation and limits

43 web tests, 37 Swift core tests, and 17 Python tests pass. Native builds and Simulator layout checks cover both phone and tablet layouts. Earlier physical-device checks exercised scientific notebooks, original-file saves, GPU calls, package installation, and installed local models. See [validation scope](VALIDATION.md) for the exact boundaries.

Current Codex/Claude Code npm distributions have no iOS target; a working on-device port is not included. Optional paired-Mac Lab execution over LAN/Tailscale still needs a passing physical-device acceptance check. The iOS console is an embedded Python/tool console, and does not provide arbitrary Unix subprocesses or every native scientific package. [Lab capabilities and setup](LAB.md).

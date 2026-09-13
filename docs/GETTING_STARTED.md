# Your first few minutes

## Open a folder

On Mac, choose **Open a vault** and select an ordinary folder. You can use the same folder in Vault and another Markdown editor. New files and saved changes become visible to Vault's watcher. Do not edit the same document simultaneously in two editors without checking for newer changes.

On iPhone/iPad, **Create a local vault** is the easiest way to get a complete offline copy. Pair it with your desktop vault in Settings. Opening a folder supplied by a third-party Files provider can inherit that provider's availability and cloud behavior; a local vault avoids that dependency.

The `examples/Welcome` folder in the source is a small, fictional library to explore safely. Real documents stay in place; development folders and hidden files are excluded from indexing and sync.

## Set up local AI

Open **Settings → Models & chat**. The Mac Starter edition already includes the smaller Qwen. Otherwise install either built-in starter model, or import an existing compatible model folder. Downloads show progress and can be paused/resumed. Keep Vault open on mobile until installation completes.

Select the installed model card, open chat, and check that the header says **On this device**. Ask a question or attach a document. Once weights are installed, this route needs no network. A **Paired Mac** model runs on the Mac and needs a working connection; it is not an offline model on your phone.

No account or API key is needed. A model download contacts Hugging Face and uses the amount of storage shown. Document text and conversations are not sent with it. See [models/README.md](../models/README.md) for offline import, exact checkpoints, and developer setup.

## Pair devices

On the first device, open **Settings → Device sync → Create pairing code**. On the second device, open its destination vault and paste the code under **Join from another device**. Keep both apps open and connected to the same local network while initial sync finishes.

Documents, saved conversations, and bookmarks sync in both directions. Once downloaded, documents are available offline. Appearance, drafts, model weights, and open tabs are device-specific. Never publish the pairing code. See [SYNC.md](SYNC.md) for edits, conflicts, deletions, and backup behavior.

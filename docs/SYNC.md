# How sync works

Vault opens an ordinary folder. On Mac, a filesystem watcher notices eligible changes made by Vault, Finder, or another editor. Periodic scans reconcile changes on mobile and changes missed while the app was closed. The index supports navigation/search; the files remain the source of truth.

Paired devices discover each other with Bonjour on the same local network, authenticate using the pairing secret, and exchange changes over an encrypted direct connection. There is no vendor-operated cloud drive, relay, or account. A pairing code grants vault access and must be kept private.

## Edits

A saved change gets a content fingerprint and a version record. Peers compare their journals, transfer changed content, verify it, and apply it atomically. This operates in both directions. If a file changes while it is being transferred, the journal detects the newer version for a later pass. If two devices edit independently, Vault preserves a visible conflict copy rather than silently choosing a winner. Review and merge conflict copies yourself.

Saved conversations and bookmarks use shared vault state and travel through sync too. Deletions are recorded and propagated; recovery copies are kept in the vault's hidden recovery area. Keep independent backups because sync also distributes unwanted edits and deletions.

## Offline and interruptions

Once a file has transferred, it is a real local file and remains readable offline. You can edit locally, then reopen both apps on the same network to sync changes. Transfers can resume after interruption. Your devices must have enough storage for the library and temporary transfer data.

On iPhone/iPad, the operating system may suspend the app or network activity in the background. Keep both apps open for the initial library transfer and when you need prompt completion. A slow first transfer may include discovery, hashing, copying, and local indexing; “indexing” is not itself proof that every peer has the same files.

## What stays device-specific

Theme, open tabs, unsaved drafts, local caches, and model weights are not document-sync content. Install a model independently on each device where you want offline AI. A paired-Mac conversation uses the Mac for inference and requires that connection; the conversation can still be saved and synced.

Hidden directories and excluded development content such as `.git`, `node_modules`, build outputs, caches, and model-weight folders remain on disk but are not treated as research documents. Copying a full folder to an external drive is a separate backup action; sync does not remove those excluded folders from your source folder.

Vault does not add file-level encryption at rest. Use the device's disk encryption and appropriate backup protection. Access to your unlocked device or exported backup can expose its local documents and conversations.

## Safari Icon Fixer 0.6.4 — Performance & Reliability

- Color Studio edits automatically enter the local draft. Review and apply when Safari is closed; no automatic Safari writes.
- Consecutive edits to one icon share an undo point. Drafts are saved after a short pause and flushed on normal exit; if saving fails, quitting warns about possible loss.
- Favorites scanning runs off the UI thread and can be canceled. Bulk downloads can also be canceled, keeping prepared icons.
- Manage backups in the app: see dates and logical sizes, restore a selected snapshot or move an older one to Trash after confirmation. The newest valid backup is protected.

The app is ad hoc signed, not Apple-notarized. Safari's cache is undocumented; compatibility is not guaranteed. Automatic updates use the existing signed Sparkle feed.

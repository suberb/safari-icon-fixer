## Safari Icon Fixer 0.7.1 — Reliability Update

- Recover interrupted cache writes from a validated pre-operation snapshot after explicit confirmation with Safari closed.
- Validate SQLite layouts and backup integrity before restoring. Legacy backups without personalization metadata keep the current protected icon collection.
- Refactored cache engine, English file names, and expanded automated tests. No change to the design or everyday workflow.

Safari must be closed before applying, resetting or restoring real icons. Safari’s cache format is undocumented; test fixtures are not proof of support for every Safari release. The app is ad hoc signed, not Apple-notarized.

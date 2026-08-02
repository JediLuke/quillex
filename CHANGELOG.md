# Changelog

## 0.7.3 — 2026-08-02

- Added explicit buffer Ref/Snapshot contracts, canonical path identity,
  duplicate-open activation, safe save/save-as, and enforced read-only buffers.
- Added standalone, embedded, and headless modes plus deferred dirty-close
  protection.
- Fixed nested input scissors, modified-codepoint leakage, undo/redo, scrollbar
  math, tab overflow, active file navigation, and per-buffer scroll restoration.
- Added reusable scroll, indentation-fold, and typed menu models.
- Added vector toolbar icons, a shared modal shell, and a FilePicker backed by
  the normal single-line TextField.
- Split pure editing, navigation, selection, search, position, and history
  logic behind the public Ref/Snapshot API.
- Made performance measurement execute work exactly once and expanded focused
  multi-repository regression coverage.

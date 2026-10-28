# Changelog

## 1.6.0 — 2026-10-28

- Paste a file path into either address bar and press Return to open a focused
  file view with its size, destination and an upload/download action.
- Open the containing folder with one click. Refresh retains file mode, and
  remembered locations and transfer destinations remain directories.
- Support explicit hidden files, relative paths, local file URLs and remote `~/`
  paths without listing the file's parent or executing a shell command.
- Keep the previous location on invalid input and discard obsolete navigation
  results. File symlinks and special files retain their existing restrictions.
- Add offline address and real SFTP queue regression checks.

## 1.5.0 — 2026-10-26

- Rename Harbor to Senda; import existing saved preferences once.
- Fix directory upload and download progress to use a whole-tree byte total and
  cumulative progress. Report the scanning phase and handle empty directories.
- Preserve final byte counts in completed queue items despite UI update throttling.
- Adapt Beautiful UI sidebar, file table, task rows and buttons to SwiftUI/AppKit.
  Share colors, spacing and radii through generated global CSS tokens.
- Add host search, offline demo fixtures, light/dark screenshots, bilingual README,
  contribution/security documentation and macOS CI checks.
- Remove personal default hosts and workspace paths.

## Earlier local versions

Harbor 1.1 added multi-selection and batch dragging. 1.2 improved interaction
performance and connection reuse. 1.3 added transfer endpoint details. 1.4 fixed
the sidebar scrollbar gutter and unified appearance.

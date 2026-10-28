# File addresses

Both address bars accept a directory or a regular file. A directory keeps the
existing browser. A file opens a focused file view with its name, size, full path,
destination directory and an explicit upload/download action. Enter resolves the
address; the action button queues the transfer. Opening the containing folder
returns to browsing. The transfer queue and collision handling remain shared.

## Design choices

- Chosen: a focused file view. One metadata lookup identifies the file without
  listing a potentially large or unreadable parent. Hidden files work explicitly.
- Considered: list the parent and select the file. This preserves more context but
  adds a directory scan and fails when the file is readable but its parent is not.
- Considered: transfer immediately on Enter. This gives no opportunity to inspect
  the destination and makes address-bar navigation unexpectedly write files.

The file view adapts the existing Beautiful UI records surface, task metadata and
capsule Button. All colors, padding, gaps and dimensions use the generated global
tokens. It supports light/dark appearances, long paths and accessible controls.

## State and resolution

Store the committed directory separately from the optional addressed file. A file
address uses its parent as that pane's transfer destination, displays its full
path in the field, and exposes a single selected entry. Never store a file path
as the remembered directory. Failed navigation leaves the previous location valid.
The latest request wins; disconnect invalidates pending remote results.

Local resolution runs off the main actor. Remote resolution uses SFTP metadata
and REALPATH on the browsing session, never a shell. Relative paths use the current
directory. Local file URLs and home paths are supported; remote ~/ uses the login
directory. Explicit file symlinks and special files remain unsupported; directory
symlinks may be browsed. File addresses do not change the global hidden-file toggle.

## Verification

Use temporary local fixtures and the system SFTP server for both panes, actual
queue uploads/downloads, empty and hidden files, Unicode/spaces, relative paths,
missing paths, symlinks/special files, stale requests and refresh/back navigation.
Check the native UI in light/dark mode with synthetic file addresses, and run the
existing protocol, selection/drag, token and performance checks with two build jobs.

# Architecture

Senda is a Swift package with no external runtime dependency.

| Area | Responsibility |
| --- | --- |
| `Sources/SFTPCore/Models.swift` | SSH alias discovery, file metadata and path safety |
| `Sources/SFTPCore/SFTP.swift` | SFTP v3 packets over system OpenSSH pipes; serial session queue |
| `Sources/SFTPCore/BrowserLocation.swift` | Directory/file address resolution without scanning a file's parent |
| `Sources/SFTPCore/TransferPlan.swift` | Immutable recursive transfer plan and cumulative byte totals |
| `Sources/Senda/AppModel.swift` | Main-actor browsing state, serial transfer queue, session reuse |
| `Sources/Senda/TransferJob.swift` | Independently observed progress and immutable source endpoints |
| `Sources/Senda/FileTable.swift` | Virtualized native tables, multi-selection and Finder file promises |
| `Sources/Senda/ContentView.swift`, `HostSidebar.swift`, `TransferRow.swift` | Workspace and Beautiful UI adaptations |
| `Sources/Senda/AddressedFileView.swift` | Focused file metadata, destination and explicit transfer action |
| `Sources/Senda/PreferencesMigration.swift` | One-time, allowlisted preference migration from Harbor |
| `Sources/Senda/Diagnostics/` | Offline checks and opt-in remote integration entry points |
| `Tests/SFTPCoreTests/` | Standalone protocol test runner, usable with Command Line Tools |

## Transfer progress

One queued file or directory has one immutable plan. Planning walks directories
once, skips descendant symlinks and sums regular-file sizes with checked arithmetic.
Remote directory listings are reused from the plan. Planning and I/O run on the
session queue, never the main actor. Cancellation is checked while planning and
between request windows.

The top-level callback emits `(0, wholeTreeBytes)`, then bytes acknowledged/written
plus the completed siblings' bytes. Descending into a new file never resets the
counter. Empty directories emit `(0, 0)` and finish normally. Files whose size
changes are rejected when detected; this is not a transactional filesystem snapshot.

UI updates are throttled to about 10 Hz and target only the observed job. The final
result carries the destination and byte counts back across the async boundary so
completion cannot overtake a throttled UI update. A failure/cancellation ends that
session; other queued tasks can reconnect.

## File addresses

Each pane stores a committed directory and an optional addressed file separately.
The address field displays the full file path, while queue destinations and saved
preferences always use the parent directory. Relative paths resolve against the
committed directory. A failed request keeps the previous location; request IDs
discard stale results, and disconnect invalidates pending remote navigation.

Local metadata and directory enumeration run in a detached task. Remote resolution
uses LSTAT, REALPATH and, for directories, READDIR on the browsing session queue.
It never interpolates an address into a shell command. An explicit hidden file
bypasses the browser filter without changing the hidden-file preference. Refresh
retains file mode and does not overwrite an address still being typed.

The focused view queues a transfer only when the user presses its action button.
It reuses the existing planning, progress, collision naming and transfer details.
The offline address checks inject a local SFTP server into the real model and
queue; ordinary application sessions continue to use system OpenSSH.

## Global design tokens

`Design/tokens.css` is the single source for colors, spacing and radii. Colors come
from Beautiful UI's `:root`/`.dark` OKLCH palette. The Tailwind unit `--spacing: 4px`
is represented as four native points; `T.space(n)` is the equivalent of multiplying
that CSS variable by `n`. This keeps native padding, gaps and dimensions tied to the
same scale. It does not add a web view or Tailwind runtime to the app.

Run `python3 scripts/generate-tokens.py` after changing tokens. The generated Swift
file is checked in; `--check` rejects stale output. `scripts/check-ui-tokens.py`
guards against hard-coded custom UI colors and spacing. Platform window chrome,
focus handling and menus remain native. Source files and component mappings are
in [third-party notices](../THIRD_PARTY_NOTICES.md).

## Performance

Both file panes use NSTableView rather than creating one SwiftUI view per file.
Filtered entries, row presentations and path-to-index lookups are cached. Same-host
queued transfers share a session, while directory browsing has its own connection.
Refreshes are coalesced and obsolete directory results are ignored.

## Documentation fixtures

Launch the built application with `--demo` (add `--dark` for dark mode). This uses
synthetic hosts, paths and jobs, bypasses SSH discovery, disables network and file
mutation actions, and uses a separate preference domain. Selection and transfer
details use the actual application views. Add `--demo-file` to show file addresses
in both panes. Quit the demo before launching normally.

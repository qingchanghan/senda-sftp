# Verification — Senda 1.7.0

Verified locally on 2026-10-28 with macOS 26.4.1, Apple silicon, Swift 6.1.2 in Swift
5 language mode. The minimum deployment target is macOS 13; a macOS 13 device and
Intel hardware have not been tested. GitHub Actions runs the offline checks,
builds the application and verifies its signature on macOS 14. See the
[CI history](https://github.com/qingchanghan/senda-sftp/actions/workflows/checks.yml)
for results for each commit.

| Check | Result |
| --- | --- |
| Global CSS ↔ Swift token parity | Passed |
| Custom UI global color/spacing guard | Passed |
| Local SFTP and throughput checks | 19 suites, 0 failures |
| Native selection, drag payload and preference migration checks | 21 checks, 0 failures |
| File-address navigation and real local SFTP queue checks | 40 checks, 0 failures |
| Transfer-speed state and notification checks | 14 checks, 0 failures |
| Live queue/detail speed and cancellation UI | Passed with synthetic transfers |
| Native address input, refresh, Esc and containing-folder interaction | Passed in 1.6.0 with disposable local files |
| Release bundle signature | `codesign --verify --deep --strict` passed |
| Binary ZIP integrity | Passed |
| Compressed DMG integrity | Passed |
| Release binary build-path removal | Passed |

The directory regression covers differently sized files across nested directories,
empty files, empty directories, skipped symlinks and root collision renaming. Every
callback retains the same whole-tree total, completed bytes never decrease, and the
last callback equals the total. Already-cancelled scans produce no destination.
Existing checks also cover cancellation cleanup and preservation of existing files.

The file-address checks cover full and relative paths, local file URLs, remote
home paths, hidden/empty files, Unicode, spaces and punctuation. They exercise
actual model queue uploads/downloads, compare file bytes, preserve colliding files,
keep file mode after refresh, and reject unsupported symlinks/special files. Files
inside non-listable parents remain addressable. Invalid paths preserve the last
valid location; obsolete requests and disconnect cannot restore stale results.
These checks use the local system SFTP server and disposable directories, without
reading SSH configuration or contacting a remote machine.

The real ProxyCommand batch check passed for 1.5.0 on 2026-10-26; it was not rerun
against a live remote host for 1.7.0. That check validates queue-model totals after
folder upload and download, binary equality, one transfer connection per three-item batch,
selection retention, native file-promise callbacks, cancelling a queued item,
resolved collision destinations, historical endpoint snapshots and failure details.
This is a native API/callback test; it does not synthesize a Finder mouse drag.

The 1.6.0 file-address UI was inspected in light and dark appearance. File metadata,
destination paths, containing-folder controls and transfer actions render in both
themes. The workspace, file-address and detail screenshots use
synthetic endpoints, show 1.58 GB / 2.4 GB for the directory task, and share the same
app views as ordinary transfers. No real hostnames or file paths appear in the
published screenshots.

The 1.6.0 release app was also exercised with disposable local files through its native
address field: paste a complete path and press Return, resolve a relative hidden
file, refresh without losing an unsubmitted edit, restore the address with Esc,
and return to the containing directory. The field and file card stayed in sync.

The 1.7.0 speed checks cover rolling-window interpolation, directory child changes,
idle decay and recovery, initial measurements, delayed UI delivery, stale samples,
large byte counters and all four adaptive unit boundaries. Job checks cover
planning, cancellation, completion/failure, copied details, uploads and downloads.
Protocol timestamps use monotonic uptime, and a half-second timer updates only the
speed label. The model emits zero window-wide notifications during those checks.

The new queue was inspected in light and dark appearance with `--demo --demo-speed`.
The detail sheet displayed the same 24.5 MB/s as the queue; cancelling the synthetic
task removed the speed label. The new screenshots show a synthetic 96 GB directory
download and contain only demo hosts and paths. The UI sample rate is simulated;
it is not a benchmark of a live SSH connection.

Performance verification uses 20,000 synthetic entries. Progress mutations emit
zero model-wide notifications, visible-entry checksum is 3,200,000, and selection
remains correct. Timing is machine-dependent; see [performance](performance.md).

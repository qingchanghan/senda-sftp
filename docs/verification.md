# Verification — Senda 1.5.0

Verified locally on 2026-10-26 with macOS 26.4.1, Apple silicon, Swift 6.1.2 in Swift
5 language mode. The minimum deployment target is macOS 13; a macOS 13 device and
Intel hardware have not been tested. GitHub Actions runs the offline checks,
builds the application and verifies its signature on macOS 14. See the
[CI history](https://github.com/qingchanghan/senda-sftp/actions/workflows/checks.yml)
for results for each commit.

| Check | Result |
| --- | --- |
| Global CSS ↔ Swift token parity | Passed |
| Custom UI global color/spacing guard | Passed |
| Local SFTP checks | 13 suites, 0 failures |
| Native selection, drag payload and preference migration checks | 21 checks, 0 failures |
| Real SSH ProxyCommand batch round trip | Passed; temporary remote/local fixtures cleaned up |
| Release bundle signature | `codesign --verify --deep --strict` passed |
| Binary ZIP integrity | Passed |

The directory regression covers differently sized files across nested directories,
empty files, empty directories, skipped symlinks and root collision renaming. Every
callback retains the same whole-tree total, completed bytes never decrease, and the
last callback equals the total. Already-cancelled scans produce no destination.
Existing checks also cover cancellation cleanup and preservation of existing files.

The real proxy-backed batch check validates queue-model totals after folder upload
and download, binary equality, one transfer connection per three-item batch,
selection retention, native file-promise callbacks, cancelling a queued item,
resolved collision destinations, historical endpoint snapshots and failure details.
This is a native API/callback test; it does not synthesize a Finder mouse drag.

The actual release UI was inspected in light and dark appearance. Host search
filters the fixture list correctly. The workspace and detail screenshots use
synthetic endpoints, show 1.58 GB / 2.4 GB for the directory task, and share the same
app views as ordinary transfers. Native tables, paths, status badges and detail
content render in both themes. No real hostnames or file paths appear in the
published screenshots.

Performance verification uses 20,000 synthetic entries. Progress mutations emit
zero model-wide notifications, visible-entry checksum is 3,200,000, and selection
remains correct. Timing is machine-dependent; see [performance](performance.md).

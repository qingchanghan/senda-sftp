# Senda 1.5 design

The accepted scope is a native rename, cumulative directory progress, Beautiful UI
adaptation and local open-source preparation.

Keep SwiftUI/AppKit and the existing OpenSSH/SFTP transport. A web-view migration
would complicate Finder promises and native table performance; isolated decorative
changes would not give a consistent design system. Instead, port SidebarNav,
RecordsTable, TaskRows and Button from the one requested library. Use the pinned
MIT source and one generated global CSS token set for both themes.

Plan directory trees once before transferring. Emit cumulative byte progress for
one queue item, preserve cancellation and collision protection, and return the
final counters with the transfer result. Cover nested and empty directories,
symlinks, cancellation, monotonic counters and real proxy-backed queue completion.

Rename the executable, package, bundle, UI and documentation to Senda. Import only
known Harbor preference keys once. Remove environment-specific connection defaults.

Prepare a bilingual README, attribution, contributor/security guidance, offline CI
and synthetic screenshots. Keep earlier local work notes and unrelated user files
outside the source archive. Public repository creation and publishing are separate
from this preparation step.

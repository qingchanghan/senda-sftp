# Third-party notices

Senda's UI adapts **Beautiful UI** by Shane Levine, licensed under the MIT License.
No other component library is copied or loaded at runtime.

- Website: https://www.beautifului.dev/
- Source: https://github.com/slev12397/beautiful-ui
- Pinned revision: `44a274e598395ab61e7c96c26fda2758780253b7`
- Retrieved: 2026-10-26
- Full license: [ThirdParty/BeautifulUI/LICENSE](ThirdParty/BeautifulUI/LICENSE)

| Upstream source | Native adaptation |
| --- | --- |
| `components/primitives/SidebarNav.tsx` | Host navigation, search field, hover and selected rows in `HostSidebar.swift` |
| `components/primitives/RecordsTable.tsx` and the records CSS | File pane surface, header, row rules, selected rows and toolbar in `FileTable.swift` / `ContentView.swift`; file address surface in `AddressedFileView.swift` |
| `components/primitives/TaskRows.tsx` | Transfer status ring, amount column and status capsules in `TransferRow.swift` |
| `components/atoms/Button.tsx` | Capsule buttons in `SendaTheme.swift`, including file address actions |
| `app/globals.css` | Color palettes and radii in `Design/tokens.css` |

Unmodified upstream reference files are in `ThirdParty/BeautifulUI/`. They are not
compiled or shipped as a JavaScript runtime. The native implementations use
SwiftUI, AppKit and system SF Symbols. They do not use the upstream icon, animation
or shadow packages.

`Design/tokens.css` is the source of truth for all custom interface colors and
spacing. `scripts/generate-tokens.py` converts OKLCH to sRGB and generates adaptive
AppKit/SwiftUI colors; a Tailwind spacing unit maps to four native points. Component
padding, gaps and dimensions use multiples of that unit. Native window chrome,
menus, focus rings and accessibility behavior remain managed by macOS.

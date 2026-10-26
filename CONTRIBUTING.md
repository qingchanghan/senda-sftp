# Contributing

Build on macOS 13+ with Swift 5.9+ and Python 3. Start with the commands in the
README; full Xcode is optional. Keep changes focused and describe the problem,
resulting behavior and verification in your pull request.

Run `./scripts/check.sh` before submitting a change. The protocol suite launches
the system SFTP server against disposable local fixtures. Native checks cover
selection, drag payloads, settings migration and update isolation. Remote tests
require an explicit SSH alias and must use disposable test directories.

## Design and architecture

- Keep SSH/protocol operations on the session queue and UI state on the main actor.
- Preserve native multi-selection, keyboard navigation and Finder file promises.
- Do not update the whole window on each transfer progress event.
- UI component adaptations must come from Beautiful UI. Record upstream source and
  license details in `THIRD_PARTY_NOTICES.md`.
- Change colors, spacing and radii in `Design/tokens.css`, then run
  `python3 scripts/generate-tokens.py`. Never hand-edit generated Swift tokens.
- Use `T.space(...)`, palette tokens and radius tokens in custom interface code.
- Use generic hosts, paths and synthetic fixtures. Do not commit SSH configs,
  credentials, proxy session data, personal downloads or build outputs.

The project uses MIT licensing. Contributions are provided under the same license.

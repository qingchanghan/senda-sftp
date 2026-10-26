# Senda development

- Senda is a native macOS SwiftUI/AppKit app, not a web app.
- Keep system OpenSSH support, including ProxyCommand and ProxyJump.
- Only adapt UI components from Beautiful UI. Preserve the pinned source, MIT
  notice and component mapping in THIRD_PARTY_NOTICES.md.
- Colors, gaps, padding, dimensions and radii in custom UI code use Design/tokens.css
  via generated Swift tokens. Run scripts/generate-tokens.py after token changes.
- Keep protocol work off the main actor and progress notifications on individual jobs.
- Use at most two Swift build jobs. Run scripts/check.sh for relevant source changes.
- Remote integration tests are opt-in and only use disposable fixture directories.
- Keep private SSH configurations, credentials, paths, local notes and downloads out
  of Git and release artifacts. Use --demo for documentation screenshots.

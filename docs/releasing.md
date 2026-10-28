# Release preparation

1. Update the version/build in `scripts/build-app.sh`, the sidebar version and changelog.
2. Run `./scripts/check.sh`. Optionally run `--batch-checks <test-alias>` against a
   disposable development account to verify the real SSH proxy path.
3. Quit Senda and run `./scripts/build-app.sh`. Verify the bundle with
   `codesign --verify --deep --strict dist/Senda.app` and test the generated ZIP.
   Release builds strip Swift's debug map before signing and reject binaries that
   still contain the checkout path, so local build paths are not distributed.
   The script also produces a verified, compressed DMG containing the app and an
   `Applications` shortcut. Mount it read-only to check the contents before release.
4. Review tracked files for private hosts, paths, credentials and unrelated files.
   Do not package the working directory with a blanket recursive ZIP command.
5. Run `python3 scripts/package-source.py`. It packages only reviewed Git-tracked
   files under a `senda-sftp/` prefix. Local notes, build products and personal
   downloads remain outside the source archive.
6. Create the intended public repository, enable private vulnerability reporting,
   and publish the reviewed source and release artifacts when authorized.

The local packaging script uses ad hoc signing. A public downloadable build may
need a Developer ID signature and Apple notarization for a smoother installation
experience. No signing identities, credentials or automatic publishing are bundled.
GitHub Actions only validates code and builds locally on the runner; it does not
publish releases.

To add a DMG to an existing release without rebuilding the app, extract its verified
ZIP into a temporary directory and run `./scripts/package-dmg.sh /path/to/Senda.app`.
The architecture is read from the app binary. Verify the mounted app's signature
and compare its files with the published ZIP, then add the DMG and its checksum to
the release. Keep the existing tag, app archives and their checksums unchanged.

## Screenshots

Quit the running app, then launch `open dist/Senda.app --args --demo` for the light
workspace, or add `--dark`. Capture the workspace and a transfer detail sheet into
`docs/images/`. These are actual app views with synthetic data, not live transfers.
Add `--demo-file` to capture the focused file-address views.
Quit the demo and launch normally afterward. Do not include real SSH aliases or
private paths in documentation screenshots.

# Release preparation

1. Update the version/build in `scripts/build-app.sh`, the sidebar version and changelog.
2. Run `./scripts/check.sh`. Optionally run `--batch-checks <test-alias>` against a
   disposable development account to verify the real SSH proxy path.
3. Quit Senda and run `./scripts/build-app.sh`. Verify the bundle with
   `codesign --verify --deep --strict dist/Senda.app` and test the generated ZIP.
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

## Screenshots

Quit the running app, then launch `open dist/Senda.app --args --demo` for the light
workspace, or add `--dark`. Capture the workspace and a transfer detail sheet into
`docs/images/`. These are actual app views with synthetic data, not live transfers.
Quit the demo and launch normally afterward. Do not include real SSH aliases or
private paths in documentation screenshots.

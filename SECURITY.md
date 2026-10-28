# Security

Senda delegates authentication, encryption, proxy commands and host verification to
macOS OpenSSH. Only use SSH configurations and ProxyCommand programs you trust.
Senda does not store authentication responses. Saved preferences contain host
aliases, browsing paths, visibility settings and an optional proxy executable PATH.

For a security issue, use the repository's **Security → Report a vulnerability**
feature once private vulnerability reporting is enabled. If it is unavailable,
open an issue asking the maintainer for a private contact without including
exploit details, secrets or affected private hostnames. Never post credentials or
full SSH/proxy logs publicly.

The current supported version is 1.7.x. This is a new project and has not received
an independent security audit. There is no telemetry, automatic update service or
credential sync.

# Changelog

All notable changes to `Infrastructure.Network.Windows` are documented in
this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org).

Add entries under `[Unreleased]` as changes merge; at release the
`[Unreleased]` heading is promoted to the new version + date and a fresh
`[Unreleased]` is opened above it. Changes prior to 0.4.0 live in the git
history and the tag list.

## [Unreleased]

## [0.4.1] - 2026-06-16

### Changed
- `Set-RouterSshPortProxy` now retries the `netsh portproxy add` via
  Common.PowerShell's `Invoke-WithExitCodeRetry`. The delete-then-add
  refresh runs unconditionally, so a transient add failure previously
  risked stranding the listen target with no rule; the bounded retry
  absorbs the transient case and still throws on a genuine failure.

### Dependencies
- Added a `RequiredModules` dependency on `Common.PowerShell` (>= 8.1.0),
  which provides `Invoke-WithExitCodeRetry`.

## [0.4.0] - 2026-06-16

### Added
- Baseline changelog. This section pins the current released surface so the
  release pipeline's changelog gate and GitHub Release have notes to anchor
  on; earlier history remains in the git log and tag list.

### Notes
- Public surface: Windows host network primitives - ICS toggling
  (`Reset-IcsSharing`, `Test-IcsDnsReachable`, `Test-IcsDnsProxyReachable`),
  netsh portproxy + firewall for router SSH (`Get-NetshPortProxyRules`,
  `Set-RouterSshPortProxy`, `Set-RouterSshPortProxyFirewall`), and
  connection-profile / WSL-router reachability probes
  (`Test-HostNetworkProfileSetting`, `Test-WslRouterReachability`).

[Unreleased]: https://github.com/VitaliiAndreev/Infrastructure-Network-Windows/compare/0.4.1...HEAD
[0.4.1]: https://github.com/VitaliiAndreev/Infrastructure-Network-Windows/compare/0.4.0...0.4.1
[0.4.0]: https://github.com/VitaliiAndreev/Infrastructure-Network-Windows/compare/0.3.0...0.4.0

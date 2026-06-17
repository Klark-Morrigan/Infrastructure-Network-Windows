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

## [1.0.0] - 2026-06-17

### Changed
- Major version bump; no functional changes (version realignment).

## [0.6.0] - 2026-06-16

### Changed
- `Set-RouterSshPortProxyFirewall` scopes its inbound 2222 allow by
  source range (`-RemoteAddress`, default `172.16.0.0/12` - the range
  WSL2's NAT allocates from) instead of by `-InterfaceAlias`. An
  interface scope pins the rule to the WSL adapter's interface GUID,
  which WSL regenerates across `wsl --shutdown` / host reboots,
  stranding the rule so WSL's SSH to the router drops until a
  re-provision. Range scoping has no interface GUID to go stale, so the
  rule survives reboots of long-lived VMs with no re-provision, while
  still keeping the router's password-auth SSH off the physical LAN and
  the Internal-switch subnet (neither sits in 172.16/12). The rule is
  refreshed (delete + re-add) each run, which also migrates an older
  interface-pinned rule.

### Added
- `Set-RouterSshPortProxyFirewall -WslNatRange` to narrow the allowed
  source range on hosts that also live on a 172.16/12 network.

### Removed
- The 0.5.0 Hyper-V Firewall rule (`New-NetFirewallHyperVRule`).
  WSL-to-host traffic is outbound from the WSL VM
  (`DefaultOutboundAction = Allow`), so the Hyper-V Firewall never gated
  it - the host's Defender rule was always the control. A leftover
  `VmProvisioner-WSL-RouterSshPortproxy-*` Hyper-V rule from a host that
  installed 0.5.0 is inert and removable with `Remove-NetFirewallHyperVRule`.

## [0.5.0] - 2026-06-16

### Changed
- `Set-RouterSshPortProxyFirewall` now also adds a Hyper-V Firewall
  allow (`New-NetFirewallHyperVRule`) scoped to WSL's VM-creator id, not
  just the Defender rule. On Windows 11 WSL "Hyper-V firewall" mode,
  WSL-to-host traffic is filtered by the Hyper-V Firewall (default-Block)
  and the Defender rule has no effect, so the portproxy was reachable
  from the host but not WSL - failing the Ansible router pre-flight with
  a TCP timeout. Both rules are idempotent and no-op when their
  preconditions are absent.

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

[Unreleased]: https://github.com/Klark-Morrigan/Infrastructure-Network-Windows/compare/1.0.0...HEAD
[1.0.0]: https://github.com/Klark-Morrigan/Infrastructure-Network-Windows/compare/0.6.0...1.0.0
[0.6.0]: https://github.com/Klark-Morrigan/Infrastructure-Network-Windows/compare/0.5.0...0.6.0
[0.5.0]: https://github.com/Klark-Morrigan/Infrastructure-Network-Windows/compare/0.4.1...0.5.0
[0.4.1]: https://github.com/Klark-Morrigan/Infrastructure-Network-Windows/compare/0.4.0...0.4.1
[0.4.0]: https://github.com/Klark-Morrigan/Infrastructure-Network-Windows/compare/0.3.0...0.4.0

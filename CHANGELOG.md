# Changelog

All notable changes to `Infrastructure.Network.Windows` are documented in
this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org).

Add entries under `[Unreleased]` as changes merge; at release the
`[Unreleased]` heading is promoted to the new version + date, a fresh
`[Unreleased]` is opened above it, and the new version gets a line in the
index below. Changes prior to 0.4.0 live in the git history and the tag list.

## Contents

- [Unreleased](#unreleased)
- [1.4.0 - 2026-07-29](#140---2026-07-29)
- [1.3.0 - 2026-06-25](#130---2026-06-25)
- [1.2.0 - 2026-06-22](#120---2026-06-22)
- [1.1.0 - 2026-06-18](#110---2026-06-18)
- [1.0.0 - 2026-06-17](#100---2026-06-17)
- [0.6.0 - 2026-06-16](#060---2026-06-16)
- [0.5.0 - 2026-06-16](#050---2026-06-16)
- [0.4.1 - 2026-06-16](#041---2026-06-16)
- [0.4.0 - 2026-06-16](#040---2026-06-16)

## [Unreleased]

### Changed

- `Get-IcsDnsFailureDiagnostics` now appends the commands that carry out its verdict, one per line, instead of describing them in prose. The wedged-proxy verdict said "re-toggle sharing", leaving the operator to rediscover that the toggle is `Reset-IcsSharing` and that it takes two interface names; it now ends with a runnable sequence (`Restart-Service` -> `Reset-IcsSharing` -> re-probe -> `Restart-Computer`). Every branch closes with the same `Resolve-DnsName` the check itself runs, so "did the fix take" no longer means re-running the whole preflight. New optional `-WanAdapterName` / `-LanAdapterName` shape the `Reset-IcsSharing` line into this host's actual invocation; without them it degrades to placeholders plus a `Get-NetAdapter` hint.
- `Test-IcsDnsProxyReachable` routes its skipped-repair FAIL (`-NoAutoRepair`, or no `-WanAdapterName`) through `Get-IcsDnsFailureDiagnostics` too, and forwards the adapter names on both FAIL paths. That path used to hand out a hardcoded "toggle the Sharing checkbox" hint regardless of whether the service was even running - a choice the diagnostics function already makes correctly.

- The two DNS probes (`Test-IcsDnsReachable`, `Test-HostDnsReachable`) were the same function written twice, differing only in whether `-Server` was passed. Both now delegate to a private `Test-DnsProbeName`, and the probe host they resolve - which operator messages print as a command to run - comes from a private `Get-DnsProbeName` rather than a literal repeated across four places. Public signatures and behaviour are unchanged. Adds a `Private/` tree to the module for internals that several exported functions share.

### Fixed

- `Test-RouterSshRelay` reported a refused connect as a generic probe error instead of "No SSH relay listening ... re-lay it with `Set-RouterSshRelay`". A refusal faults the connect task, and `Task.Wait` rethrows that rather than returning false, so at the default 5s budget the commonest failure of all - nothing listening - landed in the catch-all and lost its advice. The fault now resolves to the same verdict as an expired budget, and the socket error is quoted in the reason so a refusal is distinguishable from a silently black-holed port. The suite missed it because every nothing-listening test used a 2s budget, short enough to expire at the same instant the refusal arrived; one now probes at the default.

## [1.4.0] - 2026-07-29

### Added

- `Test-RouterSshRelay` - the read counterpart `Set-RouterSshRelay` /
  `Remove-RouterSshRelay` shipped without: until now the relay could be
  laid and torn down but never verified, so a broken one was only ever
  fixed blind by re-laying it under the preflight's `-AutoRepair` and no
  caller could report that it had been broken. Actively probes the
  host-side listen endpoint and returns a result object
  (`Ok` / `Stage` / `Banner` / `Reason`).

  It is an active probe, not a `netsh` read, because the failure it
  exists to catch is invisible to configuration inspection: an ICS toggle
  regenerates the Internal vSwitch network and leaves iphlpsvc forwarding
  bound to the previous generation, so the portproxy entry reads back
  perfectly while its onward hop is dead. Only moving bytes can see that.

  `Stage` separates the two diagnoses - `Connect` (nothing listening; the
  portproxy is absent) from `Banner` (listening but not forwarding; the
  stale-generation signature, indistinguishable from a powered-off
  router, which the `Reason` text says rather than guessing).

  Probes the listener rather than the router's own IP on purpose:
  connecting straight to `<router>:22` bypasses the relay and would
  report healthy while every WSL-side consumer is broken. Host-side
  loopback does not traverse the Windows Firewall, so the probe covers
  the portproxy and its forwarding but not the firewall companion - a
  narrow gap by design, since that rule is scoped by remote address
  rather than interface and so has nothing volatile to go stale against.

  Not a replacement for Common-Ansible's
  `ops/virtual-machines/_assert-router-reachable.sh`, which probes the
  same hop WSL-side (traversing the firewall too) and already gates every
  Ansible flow. Prefer that one from bash; this is for the host-side
  callers that run no playbook. Documentation reference only - this module
  does not consume Common-Ansible.

## [1.3.0] - 2026-06-25

### Added

- `Get-WirelessNetAdapter` - single source of truth for "which physical
  adapters are Wi-Fi" on a Windows host (matches on the driver
  `InterfaceDescription`, not the host-varying connection name). Returns
  the matching `Get-NetAdapter` objects so callers can compare MACs,
  resolve a connection name to feed `Reset-IcsSharing`'s WAN parameter,
  or check link state without each carrying its own copy of the match.
- `Set-RouterSshRelay` / `Remove-RouterSshRelay` - compose the netsh
  portproxy and its Windows Firewall companion as one inseparable pair
  (add and teardown), so a caller cannot lay/sweep one half and forget
  the other - the silent "banner exchange timeout" footgun. `Set` adds a
  `-FirewallOnly` mode for the pre-VM phase (firewall pre-laid before the
  router IP is known); both delegate to the existing
  `Set-/Remove-RouterSshPortProxy(+Firewall)` primitives.

## [1.2.0] - 2026-06-22

### Added

- `Remove-RouterSshPortProxy` - teardown counterpart to
  `Set-RouterSshPortProxy`. Removes every netsh portproxy rule forwarding
  to a given router IP (keyed on the connect target, so it sweeps relays
  under any listen address). netsh portproxy state persists across VM /
  switch teardown, so without this the rules accumulate per router IP
  across lifecycles and a stale entry can shadow the WSL relay
  auto-discovery for the next router.
- `Remove-RouterSshPortProxyFirewall` - teardown counterpart to
  `Set-RouterSshPortProxyFirewall`; removes the inbound allow rule by its
  port-keyed DisplayName so the firewall surface is torn down symmetrically
  with the portproxy.

## [1.1.0] - 2026-06-18

### Added

- `Get-IcsDnsFailureDiagnostics` - on a dead ICS DNS proxy, probes the
  two distinguishing host signals (`SharedAccess` service status + an
  upstream-side resolve via the host's own resolver) and returns the one
  fix that applies, instead of a checklist.
- `Test-HostDnsReachable` - resolves `archive.ubuntu.com` via the host's
  own configured resolver (no `-Server`), the upstream-side counterpart
  to `Test-IcsDnsReachable`. Distinguishes a wedged ICS proxy (host DNS
  works, proxy does not) from a dead host upstream (neither works), which
  need different fixes.

### Changed

- `Test-IcsDnsProxyReachable`'s terminal FAIL (proxy still unreachable
  after the one-shot `Reset-IcsSharing`) now folds
  `Get-IcsDnsFailureDiagnostics` output into the finding `Detail`, naming
  the next action (start service / fix host network / restart + reboot)
  rather than pointing the operator at a manual checklist. Signature and
  finding shape are unchanged, so callers need no update.

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

[Unreleased]: https://github.com/Klark-Morrigan/Infrastructure-Network-Windows/compare/1.3.0...HEAD
[1.3.0]: https://github.com/Klark-Morrigan/Infrastructure-Network-Windows/compare/1.2.0...1.3.0
[1.2.0]: https://github.com/Klark-Morrigan/Infrastructure-Network-Windows/compare/1.1.0...1.2.0
[1.1.0]: https://github.com/Klark-Morrigan/Infrastructure-Network-Windows/compare/1.0.0...1.1.0
[1.0.0]: https://github.com/Klark-Morrigan/Infrastructure-Network-Windows/compare/0.6.0...1.0.0
[0.6.0]: https://github.com/Klark-Morrigan/Infrastructure-Network-Windows/compare/0.5.0...0.6.0
[0.5.0]: https://github.com/Klark-Morrigan/Infrastructure-Network-Windows/compare/0.4.1...0.5.0
[0.4.1]: https://github.com/Klark-Morrigan/Infrastructure-Network-Windows/compare/0.4.0...0.4.1
[0.4.0]: https://github.com/Klark-Morrigan/Infrastructure-Network-Windows/compare/0.3.0...0.4.0

# Infrastructure.Network.Windows

Windows host network utilities for infrastructure repos.

Everything here is Windows-only — the underlying primitives (`netsh`,
`HNetCfg`, `Get-NetFirewallRule`, `Get-NetConnectionProfile`,
`Resolve-DnsName`) do not exist on other platforms.

## Contents

- [Functions](#functions)
  - [ICS](#ics)
  - [Portproxy](#portproxy)
  - [Firewall](#firewall)
  - [Profile](#profile)
  - [Probes](#probes)
- [Repository layout](#repository-layout)
- [Installation](#installation)
- [Local tests](#local-tests)
- [CI and linting](#ci-and-linting)
- [Release](#release)

## Functions

### ICS

| Function | What it does |
|---|---|
| `Reset-IcsSharing` | Programmatic equivalent of toggling the WiFi adapter's Sharing tab off + on, via `HNetCfg.HNetShare` COM. Use when ICS's DNS proxy enters its known broken state (answers UDP/53 queries with TCP RSTs) where a `Restart-Service SharedAccess` does not recover. |
| `Test-IcsDnsReachable` | Pure pass-through over `Resolve-DnsName` so probes can be mocked. Returns `$true` if the upstream resolver answered cleanly, `$false` for any error (timeout, RST, NXDOMAIN). |
| `Test-IcsDnsProxyReachable` | Layered probe + one-shot auto-repair: tests ICS DNS proxy reachability; on FAIL invokes `Reset-IcsSharing` once and re-probes. Returns a finding object `{Status; Label; Detail}` for callers to route into their own preflight surface. |

### Portproxy

| Function | What it does |
|---|---|
| `Get-NetshPortProxyRules` | Pure parser over `netsh interface portproxy show v4tov4`. Returns `[PSCustomObject]@{ ListenAddress; ListenPort; ConnectAddress; ConnectPort }` per rule. |
| `Set-RouterSshPortProxy` | Idempotent `<listen>:<port> -> <connect>:22` portproxy rule. Skips when a matching rule is already present; deletes-and-re-adds when the connect target has drifted; adds fresh when absent. Default listen `0.0.0.0:2222` so WSL2 NAT-mode guests can reach the host loopback. |

### Firewall

| Function | What it does |
|---|---|
| `Set-RouterSshPortProxyFirewall` | Windows Defender Firewall companion for `Set-RouterSshPortProxy`. Inbound TCP allow scoped by source range to the WSL NAT range (`172.16.0.0/12`, override via `-WslNatRange`), so the host's physical LAN and the router's Internal-switch subnet stay default-deny. Range scope (not `-InterfaceAlias`) is deliberate: it has no interface GUID to go stale, so it survives `wsl --shutdown` / host reboots with no re-provision. Refreshed (delete + re-add) each run, which also migrates any older interface-pinned rule. No-op when WSL is not installed. |

### Profile

| Function | What it does |
|---|---|
| `Test-HostNetworkProfileSetting` | Reads `Get-NetConnectionProfile` for a given `-InterfaceAlias`; reports PASS when category is Private/Domain. On Public, either auto-repairs to Private (default) or reports FAIL when `-NoAutoRepair` is set. Returns a finding object `{Status; Label; Detail}`. |

### Probes

| Function | What it does |
|---|---|
| `Test-WslRouterReachability` | Runs ICMP / TCP / SSH-banner probes from inside the named WSL distro and writes a structured transcript to a log path. Returns `{IcmpOk; TcpOk; SshBannerOk; LogPath}`. **Depends on `Infrastructure.Wsl`** for `Invoke-WslShell` (the WSL execution boundary). |

## Repository layout

```
Infrastructure.Network.Windows/
  Infrastructure.Network.Windows.psd1
  Infrastructure.Network.Windows.psm1
  Public/
    Ics/
      Reset-IcsSharing.ps1
      Test-IcsDnsReachable.ps1
      Test-IcsDnsProxyReachable.ps1
    Portproxy/
      Get-NetshPortProxyRules.ps1
      Set-RouterSshPortProxy.ps1
    Firewall/
      Set-RouterSshPortProxyFirewall.ps1
    Profile/
      Test-HostNetworkProfileSetting.ps1
    Probes/
      Test-WslRouterReachability.ps1
Tests/
  Ics/, Portproxy/, Firewall/, Profile/, Probes/   # mirror of Public/
.github/workflows/
  ci-yaml.yml                 # Delegates to Common-Automation reusable ci-yaml.yml
  ci-bash.yml                 # Delegates to Common-Automation reusable ci-bash.yml
scripts/
  run-ci-yaml-and-bash.sh / .bat            # MAIN local runner: full lint suite + bats tests (shared engine)
  run-lint-yaml-and-bash.sh / .bat          # Lint half only (shellcheck, actionlint, action-validator, yamllint, ansible-lint)
  run-tests-bash.sh / .bat                  # Bats test half only
  fix-permissions.sh / .bat   # Re-stage +x on tracked *.sh via the shared engine
.gitattributes                # Pins *.sh to LF and *.bat to CRLF
```

## Installation

```powershell
Install-Module Infrastructure.Network.Windows -MinimumVersion 0.1.0
Import-Module Infrastructure.Network.Windows
```

`Infrastructure.Wsl >= 0.1.0` is listed in `RequiredModules` and auto-installed
by `Install-Module` / auto-imported by `Import-Module`.

## Local tests

Requires the shared CI scaffolding from `Common-PowerShell`:

```powershell
git clone https://github.com/Klark-Morrigan/Common-PowerShell .ci-common
.\scripts\Run-Tests.ps1
```

## CI and linting

The PowerShell module is tested with Pester via `scripts\Run-Tests.ps1`. The
YAML and Bash surfaces (workflows, the `*.sh` runners) are linted by a
separate suite that delegates to **Common-Automation**, so every repo lints
against one shared engine with no per-repo config to drift.

| Workflow | Runs |
|---|---|
| `.github/workflows/ci-yaml.yml` | actionlint, action-validator, yamllint, ansible-lint |
| `.github/workflows/ci-bash.yml` | shellcheck, check-sh-executable, bats |

Each linter auto-skips when its surface is absent. To reproduce CI locally
(Git Bash + Docker), use the main runner. It runs the full lint suite AND the
bats tests - the local equivalent of this repo's `ci-yaml.yml` + `ci-bash.yml`:

```bash
# MAIN entry: full lint suite + bats tests (local ci-yaml.yml + ci-bash.yml).
scripts/run-ci-yaml-and-bash.sh              # or double-click scripts\run-ci-yaml-and-bash.bat
```

To run just one half:

```bash
# Lint half only (shellcheck, actionlint, action-validator, yamllint,
# ansible-lint). Distinct from the Pester runner Run-Tests.ps1; runs no
# PowerShell tests.
scripts/run-lint-yaml-and-bash.sh            # or double-click scripts\run-lint-yaml-and-bash.bat

# Bats test half only.
scripts/run-tests-bash.sh                    # or double-click scripts\run-tests-bash.bat

# Re-stage the +x bit on tracked *.sh files (Windows checkouts drop it,
# tripping the check-sh-executable gate).
scripts/fix-permissions.sh     # or scripts\fix-permissions.bat
```

All three runners are thin shims over Common-Automation's engine, pointed at
this repo via the `COMMON_AUTOMATION_TARGET_REPO` env var, so a sibling
checkout at `..\Common-Automation` is required. `.gitattributes` pins `*.sh`
to LF and `*.bat` to CRLF - Linux CI runners reject CRLF shebangs.

## Release

Releases are CHANGELOG.md-driven. To ship a version: promote the
`[Unreleased]` section in [CHANGELOG.md](CHANGELOG.md) to the new version +
date, bump `ModuleVersion` in
`Infrastructure.Network.Windows/Infrastructure.Network.Windows.psd1` to
match, and merge to `master`. The manifest change triggers
[`release.yml`](.github/workflows/release.yml), which checks the version is
new, asserts it matches the top CHANGELOG.md section (so notes can never lag
the release), runs the Pester unit suite and the Docker host/target
integration workflows (which scan, find no integration tests, and no-op for
this module), then tags, publishes to PSGallery, and cuts a GitHub Release
from CHANGELOG.md via Common-PowerShell's `release-tail.yml`.

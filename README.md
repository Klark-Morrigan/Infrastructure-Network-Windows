# Infrastructure.Network.Windows

Windows host network utilities for infrastructure repos.

Everything here is Windows-only — the underlying primitives (`netsh`,
`HNetCfg`, `Get-NetFirewallRule`, `Get-NetConnectionProfile`,
`Resolve-DnsName`) do not exist on other platforms.

## Contents

- [Functions](#functions)
  - [ICS](#ics)
  - [Firewall](#firewall)
- [Repository layout](#repository-layout)
- [Installation](#installation)
- [Local tests](#local-tests)

## Functions

### ICS

| Function | What it does |
|---|---|
| `Reset-IcsSharing` | Programmatic equivalent of toggling the WiFi adapter's Sharing tab off + on, via `HNetCfg.HNetShare` COM. Use when ICS's DNS proxy enters its known broken state (answers UDP/53 queries with TCP RSTs) where a `Restart-Service SharedAccess` does not recover. |
| `Test-IcsDnsReachable` | Pure pass-through over `Resolve-DnsName` so probes can be mocked. Returns `$true` if the upstream resolver answered cleanly, `$false` for any error (timeout, RST, NXDOMAIN). |
| `Test-IcsDnsProxyReachable` | Layered probe + one-shot auto-repair: tests ICS DNS proxy reachability; on FAIL invokes `Reset-IcsSharing` once and re-probes. Returns a finding object `{Status; Label; Detail}` for callers to route into their own preflight surface. |

### Firewall

| Function | What it does |
|---|---|
| `Set-RouterSshPortProxyFirewall` | Windows Firewall companion for `Set-RouterSshPortProxy`. Inbound TCP allow rule scoped to the WSL vEthernet adapter ONLY — other host NICs keep their default-deny posture. Idempotent; no-op when WSL is not installed. |

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
    Firewall/
      Set-RouterSshPortProxyFirewall.ps1
Tests/
```

## Installation

```powershell
Install-Module Infrastructure.Network.Windows -MinimumVersion 0.1.0
Import-Module Infrastructure.Network.Windows
```

`Infrastructure.Wsl >= 0.1.0` is listed in `RequiredModules` and auto-installed
by `Install-Module` / auto-imported by `Import-Module`.

## Local tests

Requires the shared CI scaffolding from `PowerShell-Common`:

```powershell
git clone https://github.com/VitaliiAndreev/PowerShell-Common .ci-common
.\scripts\Run-Tests.ps1
```

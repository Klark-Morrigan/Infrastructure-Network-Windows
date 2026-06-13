# Infrastructure.Network.Windows

Windows host network utilities for infrastructure repos.

Everything here is Windows-only — the underlying primitives (`netsh`,
`HNetCfg`, `Get-NetFirewallRule`, `Get-NetConnectionProfile`,
`Resolve-DnsName`) do not exist on other platforms.

## Contents

- [Functions](#functions)
  - [Firewall](#firewall)
- [Repository layout](#repository-layout)
- [Installation](#installation)
- [Local tests](#local-tests)

## Functions

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

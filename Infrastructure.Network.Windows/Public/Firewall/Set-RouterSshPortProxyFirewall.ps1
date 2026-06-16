<#
.NOTES
    Do not run this file directly. Dot-sourced by provision.ps1.
#>

# ---------------------------------------------------------------------------
# Set-RouterSshPortProxyFirewall
#   Idempotent firewall companion to Set-RouterSshPortProxy.
#   Without an inbound allow the portproxy listens on 0.0.0.0:<port>
#   but the firewall silently drops inbound TCP from WSL, yielding the
#   "Connection timed out during banner exchange" symptom Ansible
#   surfaces as UNREACHABLE.
#
#   Two firewall engines, one per WSL networking generation - we ensure
#   a rule in BOTH because which one is live depends on the host's WSL
#   build and the cost of the wrong guess is the same opaque timeout:
#
#     1. Windows Defender Firewall (New-NetFirewallRule), scoped to the
#        WSL vEthernet adapter. Governs WSL in the older NAT networking
#        mode.
#     2. Hyper-V Firewall (New-NetFirewallHyperVRule), scoped to WSL's
#        VM-creator id. On Windows 11 builds where WSL runs in
#        "Hyper-V firewall" mode (adapter name
#        'vEthernet (WSL (Hyper-V firewall))'), inbound from the WSL VM
#        to the host is filtered HERE, not by engine 1, and the WSL
#        VM-creator's DefaultInboundAction is Block. An adapter-scoped
#        Defender rule does nothing for that traffic - the segment-1 TCP
#        timeout in _assert-router-reachable.sh is exactly this gap.
#
#   Tight scoping on both: engine 1 binds to the WSL vEthernet adapter,
#   engine 2 to the WSL VM-creator id. The host's WiFi, Ethernet, and
#   ICS adapters keep the OS-default deny posture - a coffee-shop WiFi
#   cannot reach the router VM through either rule.
#
#   No-op on hosts without a WSL adapter (engine 1) or without the
#   Hyper-V firewall feature / a WSL VM-creator setting (engine 2), so
#   the rest of the provisioner stays usable on Linux/Mac developer
#   boxes that exercise these helpers via Pester.
# ---------------------------------------------------------------------------

# WSL's well-known Hyper-V VM-creator id. The Hyper-V Firewall scopes
# rules per VM-creator rather than per host adapter; this GUID is the
# stable identifier the WSL platform registers under. Gating engine 2
# on the presence of a setting for this id means we never strand an
# allow rule against a creator the host does not have.
$script:WslVmCreatorId = '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}'

function Set-RouterSshPortProxyFirewall {
    [CmdletBinding()]
    param(
        # Listen port the inbound rule covers. Must match the
        # Set-RouterSshPortProxy listen port - same default.
        [int] $ListenPort = 2222
    )

    $ruleName = "Vm-Provisioner: WSL -> router SSH portproxy (TCP/$ListenPort)"

    Set-WslDefenderFirewallAllow   -ListenPort $ListenPort -RuleName $ruleName
    Set-WslHyperVFirewallAllow     -ListenPort $ListenPort -RuleName $ruleName
}

# Engine 1: standard Windows Defender Firewall, scoped to the WSL
# vEthernet adapter. Governs WSL in the older NAT networking mode.
function Set-WslDefenderFirewallAllow {
    [CmdletBinding()]
    param(
        [int]    $ListenPort,
        [string] $RuleName
    )

    # Discover the WSL vEthernet adapter (if any). Get-NetAdapter
    # returns nothing on hosts without WSL installed.
    $wslAdapter = Get-NetAdapter -ErrorAction SilentlyContinue |
                  Where-Object { $_.Name -like 'vEthernet (WSL*' } |
                  Select-Object -First 1

    if (-not $wslAdapter) {
        Write-Host "  [firewall] no vEthernet (WSL*) adapter found; skipping Defender rule (WSL probably not installed)."
        return
    }

    $existing = Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "  [firewall] inbound rule '$RuleName' already present on '$($wslAdapter.Name)', skipping."
        return
    }

    Write-Host "  [firewall] adding inbound TCP/$ListenPort allow on '$($wslAdapter.Name)' (WSL-only scope)"
    New-NetFirewallRule `
        -DisplayName    $RuleName `
        -Direction      Inbound `
        -LocalPort      $ListenPort `
        -Protocol       TCP `
        -Action         Allow `
        -InterfaceAlias $wslAdapter.Name | Out-Null
}

# Engine 2: Hyper-V Firewall, scoped to WSL's VM-creator id. Governs
# WSL in the Windows 11 "Hyper-V firewall" networking mode where
# engine 1 has no effect on WSL-to-host traffic.
function Set-WslHyperVFirewallAllow {
    [CmdletBinding()]
    param(
        [int]    $ListenPort,
        [string] $RuleName
    )

    # The Hyper-V Firewall cmdlets ship only on builds that have the
    # feature; older hosts lack them entirely. Probe before use so
    # this stays a silent no-op rather than a hard error on down-level
    # Windows and on Linux/Mac Pester runs.
    if (-not (Get-Command New-NetFirewallHyperVRule -ErrorAction SilentlyContinue)) {
        Write-Host "  [hyperv-firewall] New-NetFirewallHyperVRule unavailable; skipping (no Hyper-V firewall feature)."
        return
    }

    # Confirm the host actually registers a WSL VM-creator setting
    # before adding a rule, so a non-WSL Hyper-V host (or WSL still in
    # NAT mode) does not get an orphan allow rule.
    $vmSetting = Get-NetFirewallHyperVVMSetting -Name $script:WslVmCreatorId `
                    -ErrorAction SilentlyContinue
    if (-not $vmSetting) {
        Write-Host "  [hyperv-firewall] no WSL VM-creator setting ($script:WslVmCreatorId); skipping (WSL not in Hyper-V firewall mode)."
        return
    }

    # Hyper-V rules carry a -Name (identity key) distinct from the
    # human-facing -DisplayName, so idempotency keys off -Name.
    $hyperVRuleName = "VmProvisioner-WSL-RouterSshPortproxy-$ListenPort"
    $existing = Get-NetFirewallHyperVRule -Name $hyperVRuleName -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "  [hyperv-firewall] rule '$hyperVRuleName' already present, skipping."
        return
    }

    Write-Host "  [hyperv-firewall] adding inbound TCP/$ListenPort allow for WSL VM-creator $script:WslVmCreatorId"
    New-NetFirewallHyperVRule `
        -Name        $hyperVRuleName `
        -DisplayName $RuleName `
        -Direction   Inbound `
        -VMCreatorId $script:WslVmCreatorId `
        -Protocol    TCP `
        -LocalPorts  $ListenPort `
        -Action      Allow | Out-Null
}

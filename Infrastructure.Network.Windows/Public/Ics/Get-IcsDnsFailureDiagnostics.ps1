<#
.NOTES
    Do not run this file directly. Dot-sourced by provision.ps1. Called by
    Test-IcsDnsProxyReachable when the proxy stays unreachable after repair.
#>

# ---------------------------------------------------------------------------
# Get-IcsDnsFailureDiagnostics
#   Turns a dead ICS DNS proxy into a single next action. When the proxy
#   probe fails (and Reset-IcsSharing did not recover it), three very
#   different host states produce the SAME symptom, each with a
#   different fix:
#
#     1. SharedAccess service not Running - ICS's proxy + NAT are this
#        service; if it is stopped/hung nothing answers. Fix: start it.
#     2. Host's own upstream DNS also dead - the proxy has nothing to
#        forward to. Fix: the host network (WiFi / no internet), NOT ICS.
#     3. Service Running and host DNS fine, but the proxy still does not
#        answer - the proxy itself is wedged. Fix: restart + re-toggle,
#        then reboot (ICS state is sticky).
#
#   The terminal FAIL used to hand the operator a checklist of these to
#   walk by hand; this probes the two distinguishing signals (service
#   status + an upstream-side resolve) and returns the one verdict that
#   applies, so the FAIL detail names the fix instead of the checklist.
#
#   The verdict ships the commands that carry it out, one per line, so
#   the operator can paste them rather than translate prose ("re-toggle
#   sharing") back into a cmdlet call. Every list ends with the probe
#   that decides whether the fix took, which is the step most easily
#   skipped when the steps are only described.
#
#   Read-only: Get-Service is a status read and Test-HostDnsReachable is
#   a resolve. Safe to call on the failure path without changing host
#   state further. Both signals degrade gracefully - a missing service
#   reads as 'not found', a failed resolve as $false - so gathering
#   diagnostics never masks the original proxy FAIL with an error.
# ---------------------------------------------------------------------------

function Get-IcsDnsFailureDiagnostics {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $DnsProbeTarget,

        # Adapter names only shape the Reset-IcsSharing example line, so they
        # stay optional: a caller that does not know them still gets the
        # verdict, with placeholders and a Get-NetAdapter hint in their place.
        [string] $WanAdapterName,

        [string] $LanAdapterName
    )

    # Commands are emitted one per line under the verdict prose. The indent
    # keeps the block visually attached to its finding once the caller embeds
    # it in a multi-finding error, where later lines start at column 0.
    $commandIndent = '        '

    # The verify step for every verdict: the same probe the check itself runs,
    # so "did the fix take" is answered without re-running the whole preflight.
    $probeCommand = "Resolve-DnsName archive.ubuntu.com -Server $DnsProbeTarget -DnsOnly"

    $resetCommand =
        if ($WanAdapterName -and $LanAdapterName) {
            "Reset-IcsSharing -WanInterfaceName '$WanAdapterName' " +
            "-LanInterfaceName '$LanAdapterName'"
        } else {
            "Reset-IcsSharing -WanInterfaceName '<wifi adapter>' " +
            "-LanInterfaceName '<vEthernet (switch)>'   # names: Get-NetAdapter"
        }

    $svc       = Get-Service -Name 'SharedAccess' -ErrorAction SilentlyContinue
    $svcStatus = if ($svc) { [string]$svc.Status } else { 'not found' }
    $hostDnsOk = Test-HostDnsReachable

    # Order matters: a stopped service explains everything downstream, so
    # it is reported first; a dead upstream is the next most fundamental;
    # only when both are healthy is the proxy itself the culprit.
    if ($svcStatus -ne 'Running') {
        $verdict = "SharedAccess service is '$svcStatus' (not Running) - ICS's DNS " +
                   "proxy and NAT are that service, so nothing is listening. Start " +
                   "it (elevated), then re-probe:"
        $commands = @(
            'Start-Service SharedAccess',
            $probeCommand
        )
    }
    elseif (-not $hostDnsOk) {
        $verdict = "Host's own upstream DNS cannot resolve archive.ubuntu.com either - " +
                   "the fault is the host network (WiFi DNS / no internet), not ICS. " +
                   "Toggling sharing will not help; restore host connectivity first:"
        $commands = @(
            'Get-NetConnectionProfile                          # is the WAN link up',
            'Get-DnsClientServerAddress -AddressFamily IPv4    # what the host asks',
            'Resolve-DnsName archive.ubuntu.com -DnsOnly       # host-side, no -Server',
            $probeCommand
        )
    }
    else {
        $verdict = "SharedAccess is Running and the host's own DNS resolves, but the " +
                   "proxy at $DnsProbeTarget does not answer - the ICS proxy is wedged. " +
                   "Run elevated, re-probing after each step:"
        $commands = @(
            'Restart-Service SharedAccess',
            $resetCommand,
            $probeCommand,
            'Restart-Computer   # last resort - ICS state is sticky'
        )
    }

    $commandBlock = ($commands | ForEach-Object { "$commandIndent$_" }) -join "`n"
    $hostDnsLabel = if ($hostDnsOk) { 'OK' } else { 'FAIL' }

    "SharedAccess=$svcStatus; host upstream DNS=$hostDnsLabel. $verdict`n$commandBlock"
}

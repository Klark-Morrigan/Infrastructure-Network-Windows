BeforeAll {
    # Stub Get-NetAdapter so the function can be dot-sourced and the
    # adapter inventory driven per-test on non-Windows CI agents too.
    function Get-NetAdapter { param([switch]$Physical, $ErrorAction) }

    . "$PSScriptRoot\..\..\Infrastructure.Network.Windows\Public\Adapter\Get-WirelessNetAdapter.ps1"

    function New-Adapter {
        param([string] $Name, [string] $Description)
        [PSCustomObject]@{ Name = $Name; InterfaceDescription = $Description; Status = 'Up' }
    }
}

Describe 'Get-WirelessNetAdapter' {

    It 'returns only adapters whose description identifies them as wireless' {
        Mock Get-NetAdapter {
            @(
                New-Adapter -Name 'Wi-Fi'     -Description 'Killer Wi-Fi 7'
                New-Adapter -Name 'Ethernet'  -Description 'Intel I225-V'
                New-Adapter -Name 'WLAN'      -Description 'Broadcom 802.11ac Wireless Adapter'
            )
        }

        $result = Get-WirelessNetAdapter

        @($result).Count | Should -Be 2
        $result.Name | Should -Contain 'Wi-Fi'
        $result.Name | Should -Contain 'WLAN'
        $result.Name | Should -Not -Contain 'Ethernet'
    }

    It 'matches both the WiFi and Wireless spellings' {
        Mock Get-NetAdapter {
            @(
                New-Adapter -Name 'A' -Description 'Some WiFi Card'
                New-Adapter -Name 'B' -Description 'Generic Wireless LAN'
            )
        }

        @(Get-WirelessNetAdapter).Count | Should -Be 2
    }

    It 'returns nothing when no wireless adapter is present' {
        Mock Get-NetAdapter {
            @(New-Adapter -Name 'Ethernet' -Description 'Intel I225-V')
        }

        Get-WirelessNetAdapter | Should -BeNullOrEmpty
    }

    It 'queries only physical adapters' {
        Mock Get-NetAdapter { }

        Get-WirelessNetAdapter

        Should -Invoke Get-NetAdapter -Times 1 -Exactly -ParameterFilter {
            $Physical.IsPresent
        }
    }
}

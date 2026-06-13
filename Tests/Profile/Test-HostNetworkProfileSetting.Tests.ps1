BeforeAll {
    function Get-NetConnectionProfile { param([string] $InterfaceAlias, $ErrorAction) }
    function Set-NetConnectionProfile { param([string] $InterfaceAlias, [string] $NetworkCategory) }

    . "$PSScriptRoot\..\..\Infrastructure.Network.Windows\Public\Profile\Test-HostNetworkProfileSetting.ps1"
}

Describe 'Test-HostNetworkProfileSetting' {

    It 'returns $null when no profile can be retrieved' {
        Mock Get-NetConnectionProfile { $null }
        Mock Set-NetConnectionProfile { }

        $result = Test-HostNetworkProfileSetting -InterfaceAlias 'vEthernet (Missing)'

        $result | Should -BeNullOrEmpty
        Should -Invoke Set-NetConnectionProfile -Times 0
    }

    It 'returns PASS without mutation when profile is already Private' {
        Mock Get-NetConnectionProfile {
            [PSCustomObject]@{
                InterfaceAlias  = 'vEthernet (Shared)'
                NetworkCategory = 'Private'
            }
        }
        Mock Set-NetConnectionProfile { }

        $result = Test-HostNetworkProfileSetting -InterfaceAlias 'vEthernet (Shared)'

        $result.Status | Should -Be 'PASS'
        Should -Invoke Set-NetConnectionProfile -Times 0
    }

    It 'returns PASS without mutation when profile is Domain' {
        # Domain is just as good as Private for ICS DNS-In; only
        # Public is the broken case. Pinned so a regression that
        # tightens the predicate to Private-only does not break
        # domain-joined hosts.
        Mock Get-NetConnectionProfile {
            [PSCustomObject]@{
                InterfaceAlias  = 'vEthernet (Shared)'
                NetworkCategory = 'Domain'
            }
        }
        Mock Set-NetConnectionProfile { }

        $result = Test-HostNetworkProfileSetting -InterfaceAlias 'vEthernet (Shared)'

        $result.Status | Should -Be 'PASS'
        Should -Invoke Set-NetConnectionProfile -Times 0
    }

    It 'auto-repairs Public profile to Private and returns PASS' {
        Mock Get-NetConnectionProfile {
            [PSCustomObject]@{
                InterfaceAlias  = 'vEthernet (Shared)'
                NetworkCategory = 'Public'
            }
        }
        Mock Set-NetConnectionProfile { }

        $result = Test-HostNetworkProfileSetting -InterfaceAlias 'vEthernet (Shared)'

        $result.Status | Should -Be 'PASS'
        $result.Label  | Should -Match 'auto-repaired'
        Should -Invoke Set-NetConnectionProfile -Times 1 -Exactly -ParameterFilter {
            $InterfaceAlias  -eq 'vEthernet (Shared)' -and
            $NetworkCategory -eq 'Private'
        }
    }

    It 'reports FAIL without mutation when Public AND -NoAutoRepair is set' {
        Mock Get-NetConnectionProfile {
            [PSCustomObject]@{
                InterfaceAlias  = 'vEthernet (Shared)'
                NetworkCategory = 'Public'
            }
        }
        Mock Set-NetConnectionProfile { }

        $result = Test-HostNetworkProfileSetting `
            -InterfaceAlias 'vEthernet (Shared)' -NoAutoRepair

        $result.Status | Should -Be 'FAIL'
        Should -Invoke Set-NetConnectionProfile -Times 0
    }
}

Describe 'ZabbixApi module - basic helpers' {
    BeforeAll {
        # Import module from repository root when running in CI/checks - adjust path if needed
        $modulePath = (Resolve-Path -Path ..\ZabbixApi.psm1 -ErrorAction SilentlyContinue)
        if ($modulePath) { Import-Module $modulePath -Force -Scope Global }
        else { Import-Module $PSScriptRoot\..\ZabbixApi.psm1 -Force -Scope Global -ErrorAction SilentlyContinue }
    }

    Context 'Invoke-ZabbixApi and Connect/Disconnect' {
        It 'Connect-Zabbix stores token when user.login returns token' -TestCases @(
            @{ Token='mytoken' }
        ) {
            param($Token)
            # Mock Invoke-ZabbixApi to return a token when user.login
            Mock -CommandName Invoke-ZabbixApi -MockWith { param($Method,$Params) if ($Method -eq 'user.login') { return $Token } else { return $null } }

            # Call Connect-Zabbix, expecting it to store token in module variable
            Connect-Zabbix -ApiUrl 'https://zabbix.example/api_jsonrpc.php' -Username 'Admin' -Password 'z'
            $token = (Get-Variable -Name ZabbixApiSession -Scope Script -ErrorAction SilentlyContinue).Value.AuthToken
            $token | Should -Be $Token
            Disconnect-Zabbix
        }
    }

    Context 'Resolve helpers' {
        It 'Resolve-ZabbixGroupId returns numeric id when name exists' {
            Mock -CommandName Get-ZabbixHostGroup -MockWith { return @{ groupid='10'; name='TestGroup' } }
            { Resolve-ZabbixGroupId -Names 'TestGroup' } | Should -Not -Throw
            $ids = Resolve-ZabbixGroupId -Names 'TestGroup'
            $ids | Should -Contain '10'
        }

        It 'Resolve-ZabbixTemplateId returns id for template name' {
            Mock -CommandName Get-ZabbixTemplate -MockWith { return @{ templateid='200'; host='Template OS' } }
            $ids = Resolve-ZabbixTemplateId -NamesOrIds 'Template OS'
            $ids | Should -Contain '200'
        }
    }

    Context 'User management wrappers' {
        It 'New-ZabbixUser calls Invoke-ZabbixApi (user.create) and returns response' {
            Mock -CommandName Invoke-ZabbixApi -MockWith { param($Method,$Params) if ($Method -eq 'user.create') { return @{ userids = @('123') } } else { return $null } }
            $res = New-ZabbixUser -Alias 'test' -Password 'p@ss' -Name 'Test' -GroupIds @('2')
            $res.userids | Should -Contain '123'
        }
    }
}
<#
.SYNOPSIS
  PowerShell module providing helpers to call the Zabbix 7.4 JSON-RPC API.

.DESCRIPTION
  Thin PowerShell-friendly wrapper around the Zabbix API (7.4).
  Includes:
    - Connect-Zabbix / Disconnect-Zabbix
    - Invoke-ZabbixApi (generic)
    - Host functions (get/create/update/delete)
    - Item / Trigger / Template gets
    - Group & Template name->id resolution helpers
    - User management (get/create/update/delete)
    - Action, Maintenance, DiscoveryRule wrappers
    - Helpers to simplify passing names vs ids

.NOTES
  Author: Generated for RobinBeismann
#>

# Module state
if (-not $script:ZabbixApiSession) {
    $script:ZabbixApiSession = @{
        ApiUrl = $null
        AuthToken = $null
        DefaultHeaders = @{ 'Content-Type' = 'application/json' }
    }
}
if (-not $script:ZabbixApiReqId) { $script:ZabbixApiReqId = 1 }

function Connect-Zabbix {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ApiUrl,

        [string]$Username,
        [string]$Password,
        [System.Management.Automation.PSCredential]$Credential,
        [string]$AuthToken
    )

    $script:ZabbixApiSession.ApiUrl = $ApiUrl.TrimEnd('/')
    if ($AuthToken) {
        $script:ZabbixApiSession.AuthToken = $AuthToken
        Write-Verbose "Using provided auth token."
        return $true
    }

    if (-not $Username -and $Credential) {
        $Username = $Credential.UserName
        $Password = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Credential.Password)
        )
    }

    if (-not $Username -or -not $Password) {
        throw "Username and Password are required to login unless you provide -AuthToken or -Credential."
    }

    $resp = Invoke-ZabbixApi -Method "user.login" -Params @{ user = $Username; password = $Password } -ThrowOnError
    if ($null -eq $resp) { throw "Login failed: no response." }

    $script:ZabbixApiSession.AuthToken = $resp
    Write-Verbose "Connected to Zabbix and stored auth token."
    return $true
}

function Disconnect-Zabbix {
    [CmdletBinding()]
    param()
    $script:ZabbixApiSession.AuthToken = $null
    Write-Verbose "Disconnected (cleared auth token)."
    return $true
}

function Invoke-ZabbixApi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$Method,

        $Params = @{}, 

        [int]$Id,

        [switch]$Raw,

        [switch]$ThrowOnError
    )

    if (-not $script:ZabbixApiSession.ApiUrl) {
        throw "API Url not configured. Call Connect-Zabbix -ApiUrl <url> first."
    }

    if (-not $Id) {
        $Id = [System.Threading.Interlocked]::Increment([ref]$script:ZabbixApiReqId)
    }

    $payload = @{
        jsonrpc = "2.0"
        method  = $Method
        params  = $Params
        id      = $Id
    }

    # include auth except for login and apiinfo.* methods
    if ($Method -notin @('user.login', 'user.logout') -and $Method -notlike 'apiinfo.*') {
        if (-not $script:ZabbixApiSession.AuthToken) {
            throw "No auth token present. Connect first (Connect-Zabbix) or provide an auth token."
        }
        $payload.auth = $script:ZabbixApiSession.AuthToken
    }

    $json = $payload | ConvertTo-Json -Depth 12

    try {
        $response = Invoke-RestMethod -Uri $script:ZabbixApiSession.ApiUrl -Method Post -Body $json -ContentType 'application/json' -Headers $script:ZabbixApiSession.DefaultHeaders -ErrorAction Stop
    } catch {
        throw "HTTP request failed: $($_.Exception.Message)"
    }

    if ($response.PSObject.Properties.Name -contains 'error') {
        if ($ThrowOnError) {
            $err = $response.error
            throw "Zabbix API error: code=$($err.code) message='$($err.message)' data='$($err.data)'"
        }
    }

    if ($Raw) { return $response }
    return $response.result
}

function Get-ZabbixVersion {
    [CmdletBinding()]
    param()
    Invoke-ZabbixApi -Method "apiinfo.version"
}

### Group & Template resolution helpers

function Get-ZabbixHostGroup {
    [CmdletBinding()]
    param(
        [string[]]$GroupIds,
        [string[]]$Names,
        [object]$Output = "extend"
    )
    $params = @{ output = $Output }
    if ($GroupIds) { $params.groupids = $GroupIds }
    if ($Names) { $params.filter = @{ name = $Names } }
    Invoke-ZabbixApi -Method "hostgroup.get" -Params $params -ThrowOnError
}

function Resolve-ZabbixGroupId {
    <#
    .SYNOPSIS Resolve group names to ids
    .PARAMETER Names Array of group names or ids. Strings that look numeric are passed through.
    .OUTPUTS string[] groupids
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory=$true, ValueFromPipeline=$true)][string[]]$Names)

    process {
        $resolved = @()
        foreach ($n in $Names) {
            if ($n -match '^\d+$') {
                $resolved += $n
                continue
            }
            $resp = Get-ZabbixHostGroup -Names @($n) -Output @('groupid','name') 
            if ($resp -and $resp.count -ge 1) {
                $resolved += $resp[0].groupid
            } else {
                throw "Host group '$n' not found"
            }
        }
        return $resolved
    }
}

function Get-ZabbixTemplate {
    [CmdletBinding()]
    param(
        [string[]]$TemplateIds,
        [string[]]$Names,
        [object]$Output = "extend"
    )
    $params = @{ output = $Output }
    if ($TemplateIds) { $params.templateids = $TemplateIds }
    if ($Names) { $params.filter = @{ host = $Names } }
    Invoke-ZabbixApi -Method "template.get" -Params $params -ThrowOnError
}

function Resolve-ZabbixTemplateId {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true, ValueFromPipeline=$true)][string[]]$NamesOrIds)

    process {
        $resolved = @()
        foreach ($n in $NamesOrIds) {
            if ($n -match '^\d+$') {
                $resolved += $n
                continue
            }
            $resp = Get-ZabbixTemplate -Names @($n) -Output @('templateid','name','host')
            if ($resp -and $resp.count -ge 1) {
                $resolved += $resp[0].templateid
            } else {
                throw "Template '$n' not found"
            }
        }
        return $resolved
    }
}

### Host helpers (unchanged, kept for compatibility)

function Get-ZabbixHost {
    [CmdletBinding()]
    param(
        [string[]]$HostIds,
        [string]$Host,
        [ValidateNotNull()] $InputObject,
        [Object]$Output = "extend",
        [Object]$SelectInterfaces = $null
    )

    $params = @{ output = $Output }
    if ($HostIds) { $params.hostids = $HostIds }
    if ($Host) { $params.filter = @{ host = @($Host) } }
    if ($SelectInterfaces) { $params.selectInterfaces = $SelectInterfaces }

    $result = Invoke-ZabbixApi -Method "host.get" -Params $params -ThrowOnError
    $result | ForEach-Object {
        [PSCustomObject]@{
            id = $_.hostid
            host = $_.host
            name = $_.name
            interfaces = $_.interfaces
            groups = $_.groups
            templates = $_.parentTemplates
            raw = $_
        }
    }
}

function New-ZabbixHost {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Host,
        [string]$Name,
        [Parameter(Mandatory=$true)][object[]]$Interfaces,
        [Parameter(Mandatory=$true)][object[]]$Groups,
        [object[]]$Templates
    )

    $params = @{
        host = $Host
        interfaces = $Interfaces
        groups = $Groups
    }
    if ($Name) { $params.name = $Name }
    if ($Templates) { $params.templates = $Templates }

    $resp = Invoke-ZabbixApi -Method "host.create" -Params $params -ThrowOnError
    return [PSCustomObject]@{ hostids = $resp.hostids; raw = $resp }
}

function Set-ZabbixHost {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$HostId,
        [Parameter(Mandatory=$true)][hashtable]$Properties
    )
    $body = $Properties.Clone()
    $body.hostid = $HostId
    $resp = Invoke-ZabbixApi -Method "host.update" -Params $body -ThrowOnError
    return [PSCustomObject]@{ raw = $resp }
}

function Remove-ZabbixHost {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true, Position=0)][string[]]$HostIds)
    $resp = Invoke-ZabbixApi -Method "host.delete" -Params $HostIds -ThrowOnError
    return [PSCustomObject]@{ hostids = $resp.hostids; raw = $resp }
}

function Get-ZabbixItem {
    [CmdletBinding()]
    param(
        [string[]]$ItemIds,
        [string[]]$HostIds,
        [Object]$Output = "extend"
    )
    $params = @{ output = $Output }
    if ($ItemIds) { $params.itemids = $ItemIds }
    if ($HostIds) { $params.hostids = $HostIds }
    $resp = Invoke-ZabbixApi -Method "item.get" -Params $params -ThrowOnError
    return $resp
}

function Get-ZabbixTrigger {
    [CmdletBinding()]
    param(
        [string[]]$TriggerIds,
        [string[]]$HostIds,
        [Object]$Output = "extend"
    )
    $params = @{ output = $Output }
    if ($TriggerIds) { $params.triggerids = $TriggerIds }
    if ($HostIds) { $params.hostids = $HostIds }
    $resp = Invoke-ZabbixApi -Method "trigger.get" -Params $params -ThrowOnError
    return $resp
}

### User management

function Get-ZabbixUser {
    [CmdletBinding()]
    param(
        [string[]]$UserIds,
        [string]$FilterAlias,
        [Object]$Output = "extend"
    )
    $params = @{ output = $Output }
    if ($UserIds) { $params.userids = $UserIds }
    if ($FilterAlias) { $params.filter = @{ alias = @($FilterAlias) } }
    Invoke-ZabbixApi -Method "user.get" -Params $params -ThrowOnError
}

function New-ZabbixUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Alias,
        [Parameter(Mandatory=$true)][string]$Password,
        [Parameter(Mandatory=$true)][string]$Name,
        [string]$Surname,
        [Parameter(Mandatory=$true)][string[]]$GroupIds
    )
    # Build usrgrps array required by API
    $usrgrps = $GroupIds | ForEach-Object { @{ usrgrpid = $_ } }
    $params = @{
        alias = $Alias
        passwd = $Password
        name = $Name
        usrgrps = $usrgrps
    }
    if ($Surname) { $params.surname = $Surname }
    $resp = Invoke-ZabbixApi -Method "user.create" -Params $params -ThrowOnError
    return $resp
}

function Set-ZabbixUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$UserId,
        [Parameter(Mandatory=$true)][hashtable]$Properties
    )
    $body = $Properties.Clone()
    $body.userid = $UserId
    $resp = Invoke-ZabbixApi -Method "user.update" -Params $body -ThrowOnError
    return $resp
}

function Remove-ZabbixUser {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string[]]$UserIds)
    $resp = Invoke-ZabbixApi -Method "user.delete" -Params $UserIds -ThrowOnError
    return $resp
}

### Actions

function Get-ZabbixAction {
    [CmdletBinding()]
    param(
        [string[]]$ActionIds,
        [Object]$Output = "extend"
    )
    $params = @{ output = $Output }
    if ($ActionIds) { $params.actionids = $ActionIds }
    Invoke-ZabbixApi -Method "action.get" -Params $params -ThrowOnError
}

function New-ZabbixAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][hashtable]$ActionObject
    )
    # $ActionObject must follow action.create schema from Zabbix API
    Invoke-ZabbixApi -Method "action.create" -Params $ActionObject -ThrowOnError
}

function Remove-ZabbixAction {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string[]]$ActionIds)
    Invoke-ZabbixApi -Method "action.delete" -Params $ActionIds -ThrowOnError
}

### Maintenance

function Get-ZabbixMaintenance {
    [CmdletBinding()]
    param(
        [string[]]$MaintenanceIds,
        [Object]$Output = "extend"
    )
    $params = @{ output = $Output }
    if ($MaintenanceIds) { $params.maintenanceids = $MaintenanceIds }
    Invoke-ZabbixApi -Method "maintenance.get" -Params $params -ThrowOnError
}

function New-ZabbixMaintenance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][hashtable]$MaintenanceObject
    )
    Invoke-ZabbixApi -Method "maintenance.create" -Params $MaintenanceObject -ThrowOnError
}

function Remove-ZabbixMaintenance {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string[]]$MaintenanceIds)
    Invoke-ZabbixApi -Method "maintenance.delete" -Params $MaintenanceIds -ThrowOnError
}

### Discovery rules

function Get-ZabbixDiscoveryRule {
    [CmdletBinding()]
    param(
        [string[]]$DiscoveryIds,
        [string[]]$HostIds,
        [Object]$Output = "extend"
    )
    $params = @{ output = $Output }
    if ($DiscoveryIds) { $params.discoveryids = $DiscoveryIds }
    if ($HostIds) { $params.hostids = $HostIds }
    Invoke-ZabbixApi -Method "discoveryrule.get" -Params $params -ThrowOnError
}

function New-ZabbixDiscoveryRule {
    [CmdletBinding()]
    param([hashtable]$DiscoveryObject)
    Invoke-ZabbixApi -Method "discoveryrule.create" -Params $DiscoveryObject -ThrowOnError
}



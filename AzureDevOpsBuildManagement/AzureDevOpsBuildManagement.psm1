using namespace Microsoft.PowerShell.Commands

enum BuildQueueStatus {
  disabled
  enabled
  paused
}


class RestClient {
  hidden static [RestClient] $Instance

  static [RestClient]GetInstance() {
    if ([RestClient]::Instance -eq $null) {
      [RestClient]::Instance = [HttpRestClient]::new()
    }

    return [RestClient]::Instance
  }

  [hashtable]Invoke([string]$Uri, [WebRequestMethod]$Method, [string]$Token, [hashtable]$Body = $null) {
    throw("abstract method")
  }
}

class HttpRestClient : RestClient {
  [hashtable]Invoke([string]$Uri, [WebRequestMethod]$Method, [string]$Token, [hashtable]$Body = $null) {
    $Headers = @{
      'Authorization' = "Basic $Token";
      'Content-Type' = "application/json"
    }
    return Invoke-RestMethod -Uri $Uri -Method $Method -Body $Body -Headers $Headers
  }
}

function GetSystemToken {
  $PAT = ":$env:SYSTEM_ACCESSTOKEN"
  $Bytes  = [System.Text.Encoding]::ASCII.GetBytes($PAT)
  return [System.Convert]::ToBase64String($Bytes)
}

function AzureDevOpsRestCall {
  param(
    [string]$Uri,
    [WebRequestMethod]$Method,
    [string]$Token,
    [Parameter(Mandatory=$false)][ValidateSet('none','all','cancelling','completed','inProgress','notStarted','postponed')][hashtable]$Body = $null
  )

  [RestClient]::GetInstance().Invoke($Uri, $Method, $Token, $Body)
}

function Get-AzureDevOpsBuilds {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory=$false)][string[]]$DefinitionIds = @(),
    [Parameter(Mandatory=$false)][string]$StatusFilter = ''
  )

  $Token = GetSystemToken

  $Url = "$($env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI)$env:SYSTEM_TEAMPROJECTID/_apis/build/builds?api-version=5.1"
  if ($DefinitionIds -ne 0) {
    $Url = "$Url&definitions=$DefinitionIds"
  }
  if ($StatusFilter -ne '') {
    $Url = "$Url&statusFilter=$StatusFilter"
  }
  $Builds = AzureDevOpsRestCall -Uri $Url -Method Get -Token $Token

  Write-Host 'Hi!' $Builds

  $Builds.value | ForEach-Object { "$($_._links.self.href)?api-version=5.1" }
}

function Remove-AzureDevOpsBuilds {
  [CmdletBinding()]
  param(
    [Parameter(ValueFromPipeline)][string[]]$BuildUrls
  )

  $Token = GetSystemToken

  foreach ($BuildUrl in $BuildUrls) {
    AzureDevOpsRestCall -Uri $BuildUrl -Method Delete -Token $Token
  }
}

function Set-AzureDevOpsPipelineQueueStatus {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$DefinitionId,
    [Parameter(Mandatory)][ValidateSet('enabled','disabled','paused')][string]$NewStatus
  )

  $Token = GetSystemToken
  $Url = "$($env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI)$env:SYSTEM_TEAMPROJECTID/_apis/build/definitions/$($DefinitionId)/?api-version=5.1"

  $Pipeline = AzureDevOpsRestCall -Uri $Url -Method Get -Token $Token

  $Pipeline.queueStatus = "$NewStatus"

  AzureDevOpsRestCall -Uri $Url -Method Put -Token $Token -Body ($Pipeline | ConvertTo-Json)
}

Export-ModuleMember '*-*'
Export-ModuleMember 'RestClient'
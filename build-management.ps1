enum BuildQueueStatus {
  disabled
  enabled
  paused
}

enum BuildStatus {

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

class HttpRestClient {
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
  $Builds = [RestClient]::GetInstance().Invoke($Url, 'Get', $Token)

  $Builds.value | ForEach-Object { "$($_._links.self.href)?api-version=5.1" }
}

function Remove-AzureDevOpsBuilds {
  [CmdletBinding()]
  param(
    [Parameter(ValueFromPipeline)][string[]]$BuildUrls
  )

  $Token = GetSystemToken

  foreach ($BuildUrl in $BuildUrls) {
    [RestClient]::GetInstance().Invoke($BuildUrl, 'Delete', $Token)
  }
}

function Set-AzureDevOpsPipelineQueueStatus {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$DefinitionId,
    [Parameter(Mandatory)][BuildQueueStatus]$NewStatus
  )

  $Token = GetSystemToken
  $Url = "$($env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI)$env:SYSTEM_TEAMPROJECTID/_apis/build/definitions/$($DefinitionId)/?api-version=5.1"

  $Client = [RestClient]::GetInstance()

  $Pipeline = $Client.Invoke($Url, 'Get', $Token)
  $Pipeline.queueStatus = "$NewStatus"
  $Client.Invoke($Url, 'Put', $Token, ($Pipeline | ConvertTo-Json))
}
class RestClient {
  hidden static [RestClient] $Instance

  static [RestClient]GetInstance() {
    if ([RestClient]::Instance -eq $null) {
      [RestClient]::Instance = [HttpRestClient]::new()
    }

    return [RestClient]::Instance
  }

  [object]Invoke([string]$Uri, [string]$Method, [string]$Token, [string]$Body = '') {
    throw("abstract method")
  }
}

class HttpRestClient : RestClient {
  [object]Invoke([string]$Uri, [string]$Method, [string]$Token, [string]$Body = '') {
    $Headers = @{
      'Authorization' = "Basic $Token";
      'Content-Type' = "application/json"
    }

    if ($Body -ne '') {
      return Invoke-RestMethod -Uri $Uri -Method $Method -Body $Body -Headers $Headers
    } else {
      return Invoke-RestMethod -Uri $Uri -Method $Method -Headers $Headers
    }
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
    [string]$Method,
    [string]$Token,
    [Parameter(Mandatory=$false)][string]$Body = ''
  )

  [RestClient]::GetInstance().Invoke($Uri, $Method, $Token, $Body)
}

function Get-AzureDevOpsBuilds {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory=$false)][string[]]$DefinitionIds = @(),
    [Parameter(Mandatory=$false)][ValidateSet('none','all','cancelling','completed','inProgress','notStarted','postponed')][string]$StatusFilter = ''
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

  $Builds.value | ForEach-Object { "$($_._links.self.href)?api-version=5.1" }
}

function Remove-AzureDevOpsBuilds {
  [CmdletBinding()]
  param(
    [Parameter(ValueFromPipeline)][string]$BuildUrl
  )

  process {
    $Token = GetSystemToken

    AzureDevOpsRestCall -Uri $BuildUrl -Method Delete -Token $Token
  }
}

function Remove-PendingAzureDevOpsBuildsInQueue {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$DefinitionId
  )

  Set-AzureDevOpsPipelineQueueStatus -DefinitionId $DefinitionId 'enabled'
  $ToDelete = Get-AzureDevOpsBuilds -DefinitionIds @($DefinitionId) -StatusFilter 'notStarted'
  Get-AzureDevOpsBuilds -DefinitionIds @($DefinitionId) -StatusFilter 'notStarted' | Remove-AzureDevOpsBuilds
  Set-AzureDevOpsPipelineQueueStatus -DefinitionId $DefinitionId 'paused'
}

function Set-AzureDevOpsPipelineQueueStatus {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$DefinitionId,
    [Parameter(Mandatory)][ValidateSet('enabled','disabled','paused')][string]$NewStatus
  )

  $Token = GetSystemToken
  $Url = "$($env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI)$env:SYSTEM_TEAMPROJECTID/_apis/build/definitions/$($DefinitionId)/?api-version=5.1"

  $Pipeline = @{
    queueStatus = $NewStatus
  }

  AzureDevOpsRestCall -Uri $Url -Method 'Patch' -Token $Token -Body ($Pipeline | ConvertTo-Json)
}

Export-ModuleMember '*-*'
Export-ModuleMember 'RestClient'
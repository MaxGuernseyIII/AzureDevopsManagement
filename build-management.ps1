enum BuildQueueStatus {
  disabled
  enabled
  paused
}

function GetSystemToken {
  $PAT = ":$env:SYSTEM_PAT"
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
  $Builds = Invoke-RestMethod -Uri $Url -Method Get -Headers @{
    'Authorization' = "Basic $Token";
    'Content-Type' = "application/json"
  }

  $Builds.value | ForEach-Object { "$($_._links.self.href)?api-version=5.1" }
}

function Remove-AzureDevOpsBuilds {
  [CmdletBinding()]
  param(
    [Parameter(ValueFromPipeline)][string[]]$BuildUrls
  )

  $Token = GetSystemToken

  foreach ($BuildUrl in $BuildUrls) {
    Invoke-RestMethod -Uri $BuildUrl -Method Delete -Headers @{
      'Authorization' = "Basic $Token";
      'Content-Type' = "application/json"
    }
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

  $Headers = @{
    'Authorization' = "Basic $Token";
    'Content-Type' = "application/json"
  }

  $Pipeline = Invoke-RestMethod -Uri $Url -Method Get -Headers $Headers
  Write-Host $Pipeline
  $Pipeline.queueStatus = "$NewStatus"
  Invoke-RestMethod -Uri $Url -Method Put -Body ($Pipeline | ConvertTo-Json) -Headers $Headers
}
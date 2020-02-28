using namespace Microsoft.PowerShell.Commands
using module '.\AzureDevOpsBuildManagement\AzureDevOpsBuildManagement.psm1'

class MockRestClient : RestClient {
  hidden [bool]$Permissive = $false
  hidden [hashtable]$ExpectedCalls = @{}
  hidden [string[]]$ActualCalls = @()

  [object]Invoke([string]$Uri, [string]$Method, [string]$Token, [string]$Body = '') {
    $Key = $this.ArgsToKey($Uri, $Method, $Token, $Body)

    $this.ActualCalls = $this.ActualCalls + @($Key)

    $this.GuardCall($Key)

    return $this.ExpectedCalls[$Key]
  }

  hidden [void] GuardCall([string]$Key) {
    if ($this.Permissive) {
      return
    }

    if (-not $this.ExpectedCalls.ContainsKey($Key)) {
      $ExpectedCallsJson = ConvertTo-Json $this.ExpectedCalls.Keys
      throw (
"Call not properly conditioned.
Attempted:
$Key

Expected:
$ExpectedCallsJson")
    }
  }

  [void]GivenResponseWillBe([string]$Uri, [string]$Method, [string]$Token, [string]$Body, [object]$ResponseBody) {
    $Key = $this.ArgsToKey($Uri, $Method, $Token, $Body)

    $this.ExpectedCalls[$Key] = $ResponseBody
  }

  [void]IsPermissive() {
    $this.Permissive = $true
  }

  [void]IsRestrictive() {
    $this.Permissive = $true
  }

  [void]ShouldHaveCalled([string]$Uri, [string]$Method, [string]$Token, [string]$Body) {
    $this.ActualCalls | Should -Contain $this.ArgsToKey($Uri, $Method, $Token, $Body)
  }

  hidden [object]ArgsToKey([string]$Uri, [string]$Method, [string]$Token, [string]$Body) {
    return @{
      Uri = $Uri
      Method = $Method
      Token = $Token
      Body = $Body
    } | ConvertTo-Json
  }
}

[MockRestClient]$MockRestClient = $null
[string]$CollectionUri = $null
[string]$ProjectId = $null

function AnyString {
  return [System.Guid]::NewGuid().ToString('n')
}

function GivenCollectionUri {
  return $env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI = AnyString
}

function GivenProjectId {
  return $env:SYSTEM_TEAMPROJECTID = AnyString
}

function GivenToken {
  $env:SYSTEM_ACCESSTOKEN = AnyString
  $PAT = ":$env:SYSTEM_ACCESSTOKEN"
  $Bytes  = [System.Text.Encoding]::ASCII.GetBytes($PAT)

  return [System.Convert]::ToBase64String($Bytes)
}

function GivenBuilds {
  param(
    [Parameter(ValueFromRemainingArguments, Mandatory)][string[]]$BuildUrls
  )
  $Result = @()
  foreach ($BuildUrl in $BuildUrls) {
    $Result += @(
      @{
        _links = @{
          self = @{
            href = $BuildUrl
          }
        }
      }
    )
  }

  return $Result
}

Describe "Build Management" {

  function GivenServerBuilds([Parameter(Mandatory=$false)][string]$SearchString, [string[]]$BuildUris) {
    $Value = @()
    foreach ($BuildUri in $BuildUris) {
      $Value += @(
        @{
          _links = @{
            self = @{
              href = $BuildUri
            }
          }
        }
      )
    }
  
    $MockRestClient.GivenResponseWillBe("$($CollectionUri)$ProjectId/_apis/build/builds?api-version=5.1$SearchString", 'Get', $Token, $null, @{value = $Value })
  }

  function ThenServerDeletesHappened([string[]]$Urls) {
    foreach ($Url in $Urls) {
      $MockRestClient.ShouldHaveCalled($Url, 'Delete', $Token, $null)
    }

  }

  BeforeEach {
    $MockRestClient = [MockRestClient]::new()
    [RestClient]::Instance = $MockRestClient
    $CollectionUri = GivenCollectionUri
    $ProjectId = GivenProjectId
    $Token = GivenToken
  }

  It "can list builds with no filters" {
    GivenServerBuilds '' @('x', 'y')

    $Actual = Get-AzureDevOpsBuilds

    $Actual | Should Be @('x?api-version=5.1', 'y?api-version=5.1')
  }

  It "can list builds by definitions" {
    $Defintions = @(1,2,3)
    GivenServerBuilds "&definitions=$Defintions" @('a', 'b')

    $Actual = Get-AzureDevOpsBuilds -DefinitionIds $Defintions

    $Actual | Should Be @('a?api-version=5.1', 'b?api-version=5.1')
  }

  It "can list builds by status" {
    GivenServerBuilds '&statusFilter=completed' @('r', 's', 't')

    $Actual = Get-AzureDevOpsBuilds -StatusFilter 'completed'

    $Actual | Should Be @('r?api-version=5.1', 's?api-version=5.1', 't?api-version=5.1')
  }

  It "can list builds by intersection of status and build definition" {
    $Definitions = @(1,2,3)
    GivenServerBuilds "&definitions=$Definitions&statusFilter=completed" @('l')

    $Actual = Get-AzureDevOpsBuilds -StatusFilter 'completed' -DefinitionIds $Definitions

    $Actual | Should Be @('l?api-version=5.1')
  }

  It "can delete builds" {
    $MockRestClient.IsPermissive()
    [string[]]$Urls = @(AnyString + '/1', AnyString + '/2')

    $Urls | Remove-AzureDevOpsBuilds

    ThenServerDeletesHappened($Urls)
  }

  It "can cancel a running build" {
    $MockRestClient.IsPermissive()
    $BuildId = 413
    $Status = 'Cancelling'

    Set-AzureDevopsBuildStatus $BuildId $Status

    $MockRestClient.ShouldHaveCalled("$($CollectionUri)$ProjectId/_apis/build/builds/$BuildId?api-version=5.1", "PATCH", $Token, (@{status=$Status} | ConvertTo-Json))
  }

  # It "can modify the state of a pipeline queue" {
  #   $MockRestClient.IsPermissive()
  #   [string]$DefinitionId = AnyString

  #   Set-AzureDevOpsPipelineQueueStatus -DefinitionId $DefinitionId -NewStatus 'paused'

  #   $NewDefinition = @{
  #     queueStatus ='paused'
  #   }

  #   $MockRestClient.ShouldHaveCalled("$($CollectionUri)$ProjectId/_apis/build/definitions/$($DefinitionId)/?api-version=5.1", 'Patch', $Token, ($NewDefinition | ConvertTo-Json))
  # }

  # It "can eliminate unwanted builds" {
  #   $Global:WasUnpaused = $false
  #   $DefinitionId = 33
  #   $Definitions = @($DefinitionId)

  #   Mock Set-AzureDevOpsPipelineQueueStatus -ParameterFilter { $DefinitionId -eq $DefinitionId -and $NewStatus -eq 'enabled' } { 
  #     $MockRestClient.IsRestrictive()
  #     $Global:WasUnpaused = $true
  #   }
  #   Mock Set-AzureDevOpsPipelineQueueStatus -ParameterFilter { ($DefinitionId -eq 33) -and ($NewStatus -eq 'paused') } { 
  #     $MockRestClient.IsPermissive()
  #   }

  #   GivenServerBuilds "&definitions=$Definitions&statusFilter=notStarted" @('a', 'b', 'c')
  #   $BuildUrls = Get-AzureDevOpsBuilds -DefinitionIds $Definitions -StatusFilter 'notStarted'

  #   Remove-PendingAzureDevOpsBuildsInQueue -DefinitionId $DefinitionId

  #   $Global:WasUnpaused | Should Be $true
  #   ThenServerDeletesHappened($BuildUrls)
  # }
}

Invoke-Pester
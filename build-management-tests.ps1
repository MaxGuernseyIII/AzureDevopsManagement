using namespace Microsoft.PowerShell.Commands
using module '.\AzureDevOpsBuildManagement\AzureDevOpsBuildManagement.psm1'

class MockRestClient : RestClient {
  hidden [bool]$Permissive = $false
  hidden [hashtable]$ExpectedCalls = @{}
  hidden [string[]]$ActualCalls = @()

  [hashtable]Invoke([string]$Uri, [string]$Method, [string]$Token, [string]$Body = $null) {
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

  [void]GivenResponseWillBe([string]$Uri, [string]$Method, [string]$Token, [string]$Body, [hashtable]$ResponseBody) {
    $Key = $this.ArgsToKey($Uri, $Method, $Token, $Body)

    $this.ExpectedCalls[$Key] = $ResponseBody
  }

  [void]IsPermissive() {
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

  BeforeEach {
    $MockRestClient = [MockRestClient]::new()
    [RestClient]::Instance = $MockRestClient
    $CollectionUri = GivenCollectionUri
    $ProjectId = GivenProjectId
    $Token = GivenToken
  }

  It "can list builds with no filters" {
    $MockRestClient.GivenResponseWillBe("$($CollectionUri)$ProjectId/_apis/build/builds?api-version=5.1", 'Get', $Token, $null, @{value = GivenBuilds 'x' 'y'})

    $Actual = Get-AzureDevOpsBuilds

    $Actual | Should Be @('x?api-version=5.1', 'y?api-version=5.1')
  }

  It "can list builds by definitions" {
    $Defintions = @(1,2,3)
    $MockRestClient.GivenResponseWillBe("$($CollectionUri)$ProjectId/_apis/build/builds?api-version=5.1&definitions=$Defintions", 'Get', $Token, $null, @{value = GivenBuilds 'a' 'b'})

    $Actual = Get-AzureDevOpsBuilds -DefinitionIds $Defintions

    $Actual | Should Be @('a?api-version=5.1', 'b?api-version=5.1')
  }

  It "can list builds by status" {
    $MockRestClient.GivenResponseWillBe("$($CollectionUri)$ProjectId/_apis/build/builds?api-version=5.1&statusFilter=completed", 'Get', $Token, $null, @{value = GivenBuilds 'r' 's' 't'})

    $Actual = Get-AzureDevOpsBuilds -StatusFilter 'completed'

    $Actual | Should Be @('r?api-version=5.1', 's?api-version=5.1', 't?api-version=5.1')
  }

  It "can list builds by intersection of status and build definition" {
    $Definitions = @(1,2,3)
    $MockRestClient.GivenResponseWillBe("$($CollectionUri)$ProjectId/_apis/build/builds?api-version=5.1&definitions=$Definitions&statusFilter=completed", 'Get', $Token, $null, @{value = GivenBuilds 'l'})

    $Actual = Get-AzureDevOpsBuilds -StatusFilter 'completed' -DefinitionIds $Definitions

    $Actual | Should Be @('l?api-version=5.1')
  }

  It "can delete builds" {
    $MockRestClient.IsPermissive()
    [string[]]$Urls = @(AnyString + '/1', AnyString + '/2')

    $Urls | Remove-AzureDevOpsBuilds

    foreach ($Url in $Urls) {
      $MockRestClient.ShouldHaveCalled($Url, 'Delete', $Token, $null)
    }
  }

  It "can modify the state of a pipeline queue" {
    $MockRestClient.IsPermissive()
    [string]$DefinitionId = AnyString
    $Url = "$($CollectionUri)$ProjectId/_apis/build/definitions/$($DefinitionId)/?api-version=5.1"
    $InitialDefinition = @{
      queueStatus = 'something noisy'
      otherContent = 'anything else'
    }
    $MockRestClient.GivenResponseWillBe($Url, 'Get', $Token, $null, $InitialDefinition)

    Set-AzureDevOpsPipelineQueueStatus -DefinitionId $DefinitionId -NewStatus 'paused'

    $NewDefinition = $InitialDefinition
    $NewDefinition.queueStatus ='paused'

    $MockRestClient.ShouldHaveCalled($Url, 'Put', $Token, ($NewDefinition | ConvertTo-Json))
  }
}

Invoke-Pester
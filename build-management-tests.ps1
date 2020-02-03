using namespace Microsoft.PowerShell.Commands
using module '.\AzureDevOpsBuildManagement\AzureDevOpsBuildManagement.psm1'

Import-Module Pester

class MockRestClient : RestClient {
  [hashtable]$Calls = @{}

  [hashtable]Invoke([string]$Uri, [WebRequestMethod]$Method, [string]$Token, [hashtable]$Body = $null) {
    $Key = $this.ArgsToKey($Uri, $Method, $Token, $Body)

    if (-not $this.Calls.ContainsKey($Key)) {
      $KeyJson = ConvertTo-Json $Key
      $ExpectedCallsJson = ConvertTo-Json $this.Calls.Keys
      throw (
"Call not properly conditioned.
Attempted:
$KeyJson

Expected:
$ExpectedCallsJson")
    }

    return $this.Calls[$Key]
  }

  [void]GivenResponseWillBe([string]$Uri, [WebRequestMethod]$Method, [string]$Token, [hashtable]$Body, [hashtable]$ResponseBody) {
    $Key = $this.ArgsToKey($Uri, $Method, $Token, $Body)

    $this.Calls[$Key] = $ResponseBody
  }

  hidden [object]ArgsToKey([string]$Uri, [WebRequestMethod]$Method, [string]$Token, [hashtable]$Body) {
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

  It "can change "
}

Invoke-Pester
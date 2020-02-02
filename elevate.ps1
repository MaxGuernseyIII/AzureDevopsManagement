param (
  [Parameter(Mandatory, ValueFromRemainingArguments = $true)][string[]]$Command
)

$LogFile = New-TemporaryFile
$ResultFile = New-TemporaryFile
Set-Content $ResultFile 2
Set-Content $LogFile '### BEGIN ELEVATED PROCESS OUTPUT ###'
$FinalArgumentsList = @("/c") + $Command + @(">> $LogFile && (echo 0 > $ResultFile) || (echo 1 > $ResultFile)")
Start-Process -FilePath cmd -ArgumentList $FinalArgumentsList -Wait -Verb RunAs
$Result = Get-Content $ResultFile
Get-Content $LogFile

Write-Host "Exiting with code $Result"
exit $Result

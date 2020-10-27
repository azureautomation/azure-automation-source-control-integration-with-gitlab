<#
.DESCRIPTION
    Authors: John Seerden, Wessel Kaandorp, Oscar de Groot
    Version: 1.0

    This Azure Automation runbook synchronises runbooks from GitLab source control. 
    It requires a webhook to be set up in gitLab to trigger this runbook when changes are made.

    This enables continuous integration with GitLab source control and an automation account.
.PARAMETER AutomationAccountName
    Mandatory: Automation account to which the runbooks will be uploaded
.PARAMETER ResourceGroupName
    Mandatory: Name of the Resource Group where the Automation Account lives in
.PARAMETER GitLabServer
    Mandatory: URL of the GitLab Server
.PARAMETER AccessTokenVariableName
    Mandatory: Variable Asset Name that contains the GitLab Access Token
.PARAMETER LastShaVariableName
    Mandatory: Variable Asset Name that contains the most recent SHA of the master GitLab repository's master branch.
.PARAMETER ProjectId
    Mandatory: The Project ID of the GitLab repository we are uploading files from
.EXAMPLE
& .\Sync-GitLab.ps1 -ResourceGroupName "RES-GRP-01" `
    -AutomationAccountName "AUT-ACC-01" `
    -GitLabServer "code.ogdsoftware.nl" `
    -AccessTokenVariableName "priv-token-var-01" `
    -LastShaVariableName "GitLabShaProjectID2018-AUT-ACC-01"
    -ProjectId 1234
This command will check the repository in the project with projectId 1234 on the GitLab Server for changes.
If changes to .ps1 files are observed, the script will upload the changed .ps1 files to the automation account AUT-ACC-01.
If no changes are observed to .ps1 files the script will only inform about any other changes, but not do anything to the Automation Account.
If any files have been deleted, the script will only inform about the deletion, but keep them in Azure.
Upon finishing the script will update the hash in $LastShaVariableName to reflect the current hash in GitLab.
.NOTES
    Uses GitLab API v4
    Requires AzureRM.Profile version 3.x or higher
    Requires an Azure RunAS account
    Requires the creation of a variable asset ($AccessTokenVariableName) that contains the GitLab Access Token.
    Requires the creation of a variable asset ($LastShaVariableName) that contains the most recent SHA of the GitLab repository's master branch.
    Script creates, updates and/or removes Runbooks in the Automation Account.
#>
param(
    [Parameter(Mandatory = $true)]
    [string] $ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string] $AutomationAccountName,

    [Parameter(Mandatory = $true)]
    [string] $GitLabServer,

    [Parameter(Mandatory = $true)]
    [string] $AccessTokenVariableName,

    [Parameter(Mandatory = $true)]
    [string] $LastShaVariableName,

    [Parameter(Mandatory = $true)]
    [int] $ProjectId
)

$ErrorActionPreference = 'Stop'

# Get the 'AzureRunAsConnection' Automation Connection
try {
    $AutomationConnection = Get-AutomationConnection -Name 'AzureRunAsConnection'
}
catch {
    Write-Output "Could not retrieve AutomationConnection 'AzureRunAsConnection' (Get-AutomationConnection)"
    Write-Error $_
}

# Login Azure Resource Manager with the RunAs account
try {
    $null = Add-AzureRmAccount @AutomationConnection -ServicePrincipal
}
catch {
    Write-Output "Could not connect to AzureRm (Add-AzureRmAccount)"
    Write-Error $_
}

# Retrieve GitLab Access Token from Automation Account Variable Asset
try {
    $AccessToken = Get-AutomationVariable -Name $AccessTokenVariableName
}
catch {
    Write-Output "Could not retrieve Access Token Automation Variable '$AccessTokenVariableName' (Get-AutomationVariable)"
    Write-Error $_
}

# Get the SHA of the commit that was deployed during the previous run of this script
try {
    $PreviousMasterSha = Get-AutomationVariable -Name $LastShaVariableName
}
catch {
    Write-Output "Could not retrieve Last SHA Automation Variable '$LastShaVariableName' (Get-AutomationVariable)"
    Write-Error $_
}

# Get the SHA of current master
$CurrentMasterUri = "https://$GitLabServer/api/v4/projects/$ProjectId/repository/commits/master?private_token=$AccessToken"
try {
    $CurrentMasterResponse = Invoke-RestMethod -Method "GET" -Uri $CurrentMasterUri
}
catch {
    Write-Output 'Failed to obtain the current SHA of the master branch'
    Write-Error -Message "StatusCode: $($_.Exception.Response.StatusCode.value__). StatusDescription: $($_.Exception.Response.StatusDescription)"
}
$CurrentMasterSha = $CurrentMasterResponse.id

# Compare changes in the GitLab repository
# https://docs.gitlab.com/ee/api/repositories.html#compare-branches-tags-or-commits
$CompareUri = "https://$GitLabServer/api/v4/projects/$ProjectId/repository/compare?from=$PreviousMasterSha&to=$CurrentMasterSha&private_token=$AccessToken"
try {
    $CompareResponse = Invoke-RestMethod -Method "GET" -Uri $CompareUri
    Write-Output "Info: Fetching the list of files that were modified since the last run"
}
catch {
    Write-Output 'Failed to compare the changes in the GitLab repository'
    Write-Error -Message "StatusCode: $($_.Exception.Response.StatusCode.value__). StatusDescription: $($_.Exception.Response.StatusDescription)"
}

# Synchronise all modified files to Azure Automation Account
if ($CompareResponse.diffs) {
    Write-Output "Info: Synchronising Runbooks to Automation Account $AutomationAccountName"
    foreach ($FileDiff in $CompareResponse.diffs) {
        # If the file is a PowerShell script (.ps1)
        if ($FileDiff.new_path -like "*.ps1") {
            # Generate the Runbook name without .ps1
            $RunbookName = [io.path]::GetFileNameWithoutExtension($FileDiff.new_path)

            # If the file was removed from GitLab
            if ($FileDiff.deleted_file) {
                # Remove the Runbook from Azure Automation
                try {                  
                    $null = Remove-AzureRmAutomationRunbook -Name $RunbookName -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Force
                    Write-Output "Removed Runbook $RunbookName"
                }
                catch {
                    if($_ -like '*The Runbook was not found*') {
                        Write-Output "The Runbook '$RunbookName' was already deleted from Azure Automation."
                    } else {
                        Write-Output "Failed to remove Runbook '$RunbookName'"
                        Write-Error $_ -ErrorAction Continue
                    }
                }
                # Continue to the next PowerShell script in the foreach loop.
                continue
            }

            # Grab the file's contents.
            # > (...) GET /projects/:id/repository/files/:file_path?ref=:sha (...)
            $FileUri = "https://$GitLabServer/api/v4/projects/$ProjectId/repository/files/$($FileDiff.new_path)?ref=$CurrentMasterSha&private_token=$AccessToken"
            try {
                $Base64EncodedFileContents = Invoke-RestMethod -Method "GET" -Uri $FileUri
            }
            catch {
                Write-Output "Failed to get the content of $($FileDiff.new_path). Skipping this Runbook"
                Write-Error -Message "StatusCode: $($_.Exception.Response.StatusCode.value__). StatusDescription: $($_.Exception.Response.StatusDescription)" -ErrorAction Continue
                continue
            }
            $FileContents = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Base64EncodedFileContents.content))

            # Check if a Runbook with this name already exists for restoring Tags later
            $Runbook = Get-AzureRmAutomationRunbook -Name $RunbookName -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -ErrorAction SilentlyContinue

            # Save to file in TEMP Folder
            $Target = Join-Path $Env:Temp -Childpath $([io.path]::GetFileName($FileDiff.new_path))
            $FileContents | Out-File $Target

            # Importing the Runbook
            try {
                $null = Import-AzureRmAutomationRunbook -Path $Target -Name $RunbookName -Type PowerShell -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Published:$true -Force
                Write-Output "Imported $($FileDiff.new_path) as Runbook $RunbookName"
            }
            catch {
                Write-Output "Failed to import Runbook '$RunbookName'"
                Write-Error $_ -ErrorAction Continue
            }

            # If the Runbook had any Tags set, restore them.
            if ($Runbook) {
                try {
                    $null = Set-AzureRmAutomationRunbook -Name $Runbook.Name -Tags $Runbook.Tags
                }
                catch {
                    Write-Output "Failed to Restore Tags '$($Runbook.Tags)' for Runbook '$RunbookName'"
                    Write-Error $_ -ErrorAction Continue
                }
            }
        }
    }
} 
else {
    Write-Output "No scripts were changed, no action required."
}

# All done. Store the SHA of the commit that we've just deployed in the Variable Asset.
try {
    Set-AutomationVariable -Name $LastShaVariableName -Value $CurrentMasterSha
}
catch {
    Write-Output "Error: Could not store most recent SHA to Variable Asset '$LastShaVariableName' (Set-AutomationVariable)"
    Write-Error $_
}
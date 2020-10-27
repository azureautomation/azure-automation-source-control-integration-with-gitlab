Azure Automation source control integration with GitLab
=======================================================

            

This Azure Automation runbook synchronises runbooks from GitLab source control.
It requires a webhook to be set up in GitLab to trigger this runbook when changes are made.

This enables continuous integration with GitLab source control and an automation account.



Changes to the master branch in a GitLab repository will trigger this Azure Automation runbook using a webhook. The runbook will compare the changes in that repository between the most recent commit and the last commit since the runbook’s last
 runtime, based on their Secure Hash Algorithm (SHA) values. All changes in GitLab (new, updated or removed scripts) will be reflected in the Azure Automation account.
 

All PowerShell Scripts (.ps1) files in the root of the GitLab repository will use their scripts base name as Runbook name in the Azure Automation account.


See my blogpost for instructions on how to use here: [https://www.srdn.io/2018/08/using-gitlab-as-source-control-provider-for-azure-automation/](https://www.srdn.io/2018/08/using-gitlab-as-source-control-provider-for-azure-automation/)


 



** *** *


        
    
TechNet gallery is retiring! This script was migrated from TechNet script center to GitHub by Microsoft Azure Automation product group. All the Script Center fields like Rating, RatingCount and DownloadCount have been carried over to Github as-is for the migrated scripts only. Note : The Script Center fields will not be applicable for the new repositories created in Github & hence those fields will not show up for new Github repositories.

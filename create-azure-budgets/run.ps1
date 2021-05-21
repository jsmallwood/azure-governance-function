# Input bindings are passed in via param block.
param($Timer)

# Get the current universal time in the default string format
$currentUTCtime = (Get-Date).ToUniversalTime()

# The 'IsPastDue' porperty is 'true' when the current function invocation is later than scheduled.
if ($Timer.IsPastDue) {
#region Variables

    #region Script Variables
    [Array] $objTagNames = @()
    [Array] $objContactEmails = @()
    #endregion

    #region Management Group Id
    $rootMG = Get-AzManagementGroup -ErrorAction Stop | Where-Object {($_.DisplayName -eq 'Tenant Root Group')}

    if (($env:BUDGET_MANAGEMENT_GROUP -eq 'Tenant Root Group') -or ($env:BUDGET_MANAGEMENT_GROUP -eq '')) {
        $ManagementGroupId = $rootMG.Name
    } else {
        (Get-AzManagementGroup -GroupId $rootMG.Name -Expand -Recurse -ErrorAction Stop).Children | % {
            if (($_.Type -match 'managementGroups') -and (($_.Name -eq $env:BUDGET_MANAGEMENT_GROUP) -or ($_.DisplayName -eq $env:BUDGET_MANAGEMENT_GROUP))) { $ManagementGroupId = $_.Name }
        }
    }
    #endregion

    #region Budget Tag Names
    if ( !($env:BUDGET_TAG_NAMES) )
    {
        $env:BUDGET_TAG_NAMES = 'CostCenter'
    }
    else
    {
        if ($env:BUDGET_TAG_NAMES.Contains(',') )
        {
            $env:BUDGET_TAG_NAMES.Split(',') | % {
                $objTagNames += $_.TrimStart(' ')
            }
        }
        else
        {
            $objTagNames += $env:BUDGET_TAG_NAMES
        }
    }
    #endregion

    #region Contact Emails
    if( !($env:BUDGET_CONTACT_EMAILS) )
    {
        if((Get-AzContext -ErrorAction Stop).Account.Type -eq "User")
        {
            $objContactEmails += (Get-AzContext -ErrorAction Stop).Account.Id
        } else {
            (Get-AzTenant).Domains | % {
                if (($_ -notmatch 'mail.onmicrosoft.com') -or ($_ -notmatch 'mail.onmicrosoft.com')) { $objContactEmails = "azure-budgets@$_" }
            }
        }
    }
    else
    {
        if ( $env:BUDGET_CONTACT_EMAILS.Contains(',') )
        {
            $env:BUDGET_CONTACT_EMAILS.Split(',') | % {
                $objContactEmails += $_.TrimStart(' ')
            }
        }
        else
        {
            $objContactEmails += $env:BUDGET_CONTACT_EMAILS
        }
    }
    #endregion

    #region Location

    $function = (Get-AzResource -Name $env:WEBSITE_SITE_NAME -ErrorAction Stop)
    if(!($env:BUDGET_LOCATION) -or ($env:BUDGET_LOCATION = '')) { $BUDGET_LOCATION = $function.Location } else { $BUDGET_LOCATION = $env:BUDGET_LOCATION }

    #endregion

#endregion


#region Enumerate Tag Names
foreach ($tagName in $objTagNames)
{
    Write-Output $tagName
    #region Enumerate Tag Values
    $objTagValues = (Get-AzTag -Name $tagName -ErrorAction Stop).Values

    foreach ($value in $objTagValues)
    {

        Write-Output "Tag Name: $tagName - Tag Value: $value"
        if((($env:BUDGET_SCOPE -eq 'ManagementGroup') -or ($env:BUDGET_SCOPE -eq '')) -and ( $env:BUDGET_MANAGEMENT_GROUP_NAME -ne '' ))
        {
            Write-Output "Deploy to Management Group"
            $objParameters = @{
                tagName = "$($tagName)"
                tagValue = "$($value.Name)"
                contactEmails = $objContactEmails
            }

            try {

                Invoke-RestMethod -Method Get -Uri $env:BUDGET_MANAGEMENT_GROUP_TEMPLATE_URL -ErrorAction Stop
                Write-Output "Deploying Budget"
                New-AzManagementGroupDeployment -Name "budget-$($tagName)-$($value.Name)" `
                    -Location $BUDGET_LOCATION `
                    -ManagementGroupId $ManagementGroupId `
                    -TemplateUri $env:BUDGET_MANAGEMENT_GROUP_TEMPLATE_URL `
                    -TemplateParameterObject $objParameters `
                    -ErrorAction Stop
            } Catch {
                Write-Error $_
            }
        }
    }
    #endregion
}
#endregion

}

# Write an information log with the current time.
Write-Host "PowerShell timer trigger function ran! TIME: $currentUTCtime"

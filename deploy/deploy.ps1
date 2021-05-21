[CmdletBinding()]
param (
    [String] $ResourceGroupName = 'rg-governance',
    [String] $ManagementGroupName = '',
    [String] $Location = 'East US 2',
    [String] $TemplateFile = "https://raw.githubusercontent.com/jsmallwood/azure-function-governance/main/deploy/azureDeploy.json"
)


#region Create Resource Group Name if Default
if($ResourceGroupName -eq 'rg-governance')
{
    $ResourceGroupName = "$($ResourceGroupName)-$($Location.Replace(' ', '').ToLower())"
}
#endregion

#region Create Resource Group if it does not Exist
if(!(Get-AzResourceGroup -Name $ResourceGroupName -Location $Location))
{
    New-AzResourceGroup -Name $ResourceGroupName -Location $Location -Verbose
}
#endregion

#region Deploy ARM Template
if ($TemplateFile -match "^((http[s]?|ftp):\/)?\/?([^:\/\s]+)((\/\w+)*\/)([\w\-\.]+[^#?\s]+)(.*)?(#[\w\-]+)?$")
{
   try
   {
        Invoke-RestMethod -Method Get -Uri $templateFile -ErrorAction Stop
    }
    catch
    {
        Write-Error "The Template Uri is not valid!"
        $continue = $false
    }

    if($continue -ne $false)
    {
        New-AzResourceGroupDeployment `
            -ResourceGroupName $ResourceGroupName `
            -TemplateUri $TemplateFile `
            -Verbose
    }
} else {
    New-AzResourceGroupDeployment `
        -ResourceGroupName $ResourceGroupName `
        -TemplateUri $TemplateFile `
        -Verbose
}
#endregion

#region Get Management Group ID
if($ManagementGroupName -eq '')
{
    $ManagementGroup = (Get-AzManagementGroup)[0]
}
else {
    $ManagementGroup = (Get-AzManagementGroup -GroupId $ManagementGroupName)
}
#endregion

#region Assign RBAC Role for Azure Function Identity on Management Group
if(!($ManagementGroup))
{
    Write-Error "Please add a valid Management Group"
} else {
$functionApp = (Get-AzFunctionApp | Where-Object { $_.ResourceGroupName -eq $ResourceGroupName })

$managedIdentity = (Get-AzADServicePrincipal -SearchString "$($functionApp.Name)").Id

New-AzRoleAssignment -ObjectId $managedIdentity -RoleDefinitionName 'Reader' -Scope "$($ManagementGroup.Id)" -Verbose
New-AzRoleAssignment -ObjectId $managedIdentity -RoleDefinitionName 'Tag Contributor' -Scope "$($ManagementGroup.Id)" -Verbose
}
#endregion
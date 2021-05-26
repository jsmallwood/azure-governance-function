using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

# Interact with query parameters or the body of the request.
$name = $Request.Query.Name
if (-not $name) {
    $name = $Request.Body.Name
}

$body = "This HTTP triggered function executed successfully. Pass a name in the query string or in the request body for a personalized response."

if ($name) {
    if(!(Get-AzResourceGroup | Where {$_.ResourceGroupName -eq $name}))
    {
        Write-Output "Resource Group Does Not Exist"
        New-AzResourceGroup -Name $name -Location 'eastus2'
        Write-Output "Resource Group Created"
    }
}

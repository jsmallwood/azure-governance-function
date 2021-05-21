# Input bindings are passed in via param block.
param($eventGridEvent, $TriggerMetadata)

if (!($env:CREATED_BY_TAG_NAME)) { $CreatedByTagName = 'CreatedBy' } else { $CreatedByTagName = $env:CREATED_BY_TAG_NAME }

if ($eventGridEvent.data.authorization.evidence.principalType -eq 'ServicePrincipal')
{
    try {
        $createdBy = (Get-AzADServicePrincipal -ObjectId $eventGridEvent.data.authorization.evidence.principalId -ErrorAction Stop).DisplayName
    } catch {
        $createdBy = $eventGridEvent.data.authorization.evidence.principalId
    }
} else {
    if ($eventGridEvent.data.claims.'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress' -match "strin") {
        $createdBy = $eventGridEvent.data.claims.'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress'
    } elseif ($eventGridEvent.data.claims.'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name' -match "[^@ \t\r\n]+@[^@ \t\r\n]+\.[^@ \t\r\n]+") {
        $createdBy = $eventGridEvent.data.claims.'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name'
    } elseif ($eventGridEvent.data.claims.'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/upn' -match "[^@ \t\r\n]+@[^@ \t\r\n]+\.[^@ \t\r\n]+") {
        $createdBy = $eventGridEvent.data.claims.'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/upn'
    } else {
        $createdBy = $eventGridEvent.data.claims.name
    }
}

if($eventGridEvent.data.resourceUri -match 'resourceGroups')
{
    $resource = (Get-AzResourceGroup | Where {$_.ResourceGroupName -eq $eventGridEvent.data.resourceUri.Split('/')[4] })
} else {
    $resource = Get-AzResource -ResourceId "$($eventGridEvent.data.resourceUri)"
}

If ($resource)
{
    Write-Output "Resource was retrieved"
    Write-Output "ResourceId: $($resource.ResourceId)"
    if($resource.Tags.ContainsKey("$($CreatedByTagName)") -eq $false)
    {
        try {
            New-AzTag -ResourceId $resource.ResourceId -Tag @{"$($CreatedByTagName)" = $createdBy} -ErrorAction Stop
            Write-Output "Resource: $($resource.resourceId) updated."
        } Catch {
            Write-Error "Encountered error writing tag, may be a resource that does not support tags."
        }
    } else {
        Write-Information "Resource: $($resource.ResourceId) was not updated."
    }
}
else {
    Write-Output 'Excluded resource type'
}
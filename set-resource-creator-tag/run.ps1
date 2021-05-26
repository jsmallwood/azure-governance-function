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

    if ( ($eventGridEvent.data.claims.'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name') -and ($eventGridEvent.data.claims.'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name' -match "[^@ \t\r\n]+@[^@ \t\r\n]+\.[^@ \t\r\n]+") ) {
        $createdBy = $eventGridEvent.data.claims.'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name'
    } elseif ( ($eventGridEvent.data.claims.'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/upn') -and ( $eventGridEvent.data.claims.'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/upn' -match "[^@ \t\r\n]+@[^@ \t\r\n]+\.[^@ \t\r\n]+") ) {
        $createdBy = $eventGridEvent.data.claims.'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/upn'
    } elseif ( ($eventGridEvent.data.claims.'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress') -and ($eventGridEvent.data.claims.'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress' -match "[^@ \t\r\n]+@[^@ \t\r\n]+\.[^@ \t\r\n]+") ) {
        $createdBy = $eventGridEvent.data.claims.'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress'
    } else {
        $createdBy = $eventGridEvent.data.claims.name
    }
}

Write-Output "CreatedBy: $($createdBy)"
Write-Output "CreatedByTagName: $($CreatedByTagName)"
Write-Output "ResourceUri: $($eventGridEvent.data.resourceUri)"

try {
    $objTags = (Get-AzTag -ResourceId $eventGridEvent.data.resourceUri -ErrorAction Stop).Properties.TagsProperty

    Write-Output "Resource Tags were retrieved"

    if ( $objTags.Count -eq 0 ) {
        Write-Output "Resource does not have any tags"
        Update-AzTag -Operation Merge -ResourceId $eventGridEvent.data.resourceUri -Tag @{"$($CreatedByTagName)" = "$($createdBy)"} -ErrorAction Stop
        Write-Output "Resource was Tagged."
    } elseif ( !($objTags.Keys.Contains($CreatedByTagName)) ) {
        Write-Output "Resource does not have the $($CreatedByTagName) tag."
        Update-AzTag -Operation Merge -ResourceId $eventGridEvent.data.resourceUri -Tag @{"$($CreatedByTagName)" = "$($createdBy)"} -ErrorAction Stop
        Write-Output "Resource was Tagged."
    } else {
        Write-Output "Tag exists"
    }
} catch {
    Write-Error $_
}

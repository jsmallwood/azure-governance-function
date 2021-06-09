param([System.Collections.Hashtable] $QueueItem, $TriggerMetadata)
Write-Output "Queue Item Received"
if (!($env:CREATED_BY_TAG_NAME)) { $CreatedByTagName = 'CreatedBy' } else { $CreatedByTagName = $env:CREATED_BY_TAG_NAME }



Write-Output "CreatedByTagName: $($CreatedByTagName)"
Write-Output $QueueItem.data.resourceUri

if ($QueueItem.data.authorization.evidence.principalType -eq 'ServicePrincipal')
{
    try {
        $createdBy = (Get-AzADServicePrincipal -ObjectId $QueueItem.data.authorization.evidence.principalId -ErrorAction Stop).DisplayName
    } catch {
        $createdBy = $QueueItem.data.authorization.evidence.principalId
    }
} else {

    if ( ($QueueItem.data.claims.'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name') -and ($QueueItem.data.claims.'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name' -match "[^@ \t\r\n]+@[^@ \t\r\n]+\.[^@ \t\r\n]+") ) {
        $createdBy = $QueueItem.data.claims.'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name'
    } elseif ( ($QueueItem.data.claims.'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/upn') -and ( $QueueItem.data.claims.'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/upn' -match "[^@ \t\r\n]+@[^@ \t\r\n]+\.[^@ \t\r\n]+") ) {
        $createdBy = $QueueItem.data.claims.'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/upn'
    } elseif ( ($QueueItem.data.claims.'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress') -and ($QueueItem.data.claims.'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress' -match "[^@ \t\r\n]+@[^@ \t\r\n]+\.[^@ \t\r\n]+") ) {
        $createdBy = $QueueItem.data.claims.'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress'
    } else {
        $createdBy = $QueueItem.data.claims.name
    }
}

Write-Output "CreatedBy: $($createdBy)"
Write-Output "CreatedByTagName: $($CreatedByTagName)"
Write-Output "ResourceUri: $($QueueItem.data.resourceUri)"

trap {
    Get-AzSubscription -SubscriptionId $QueueItem.data.subscriptionId -ErrorAction Stop | Set-AzContext
}

try {
    $objTags = (Get-AzTag -ResourceId $QueueItem.data.resourceUri -ErrorAction Stop).Properties.TagsProperty

    Write-Output "Resource Tags were retrieved"

    if ( $objTags.Count -eq 0 ) {
        Write-Output "Resource does not have any tags"
        Update-AzTag -Operation Merge -ResourceId $QueueItem.data.resourceUri -Tag @{"$($CreatedByTagName)" = "$($createdBy)"} -ErrorAction Stop
        Write-Output "Resource was Tagged."
    } elseif ( !($objTags.Keys.Contains($CreatedByTagName)) ) {
        Write-Output "Resource does not have the $($CreatedByTagName) tag."
        Update-AzTag -Operation Merge -ResourceId $QueueItem.data.resourceUri -Tag @{"$($CreatedByTagName)" = "$($createdBy)"} -ErrorAction Stop
        Write-Output "Resource was Tagged."
    } else {
        Write-Output "Tag exists"
    }
} catch {
    Write-Error $_
}

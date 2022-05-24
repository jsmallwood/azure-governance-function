<#
    #Requires AzTable

#>



$storageAccountName = ''
$storageAccountKey = ''
$resourceGroupName = ''
$tableName = ''
$queueName = ''
$tagName = "CreatedBy"

$Subscriptions = Get-AzSubscription | Where-Object { $_.State -eq 'Enabled' } | % { "$($_.Id)" }

$ARGPageSize = 1000

$ARGResults = @()
$taggedResults = @()

$argQuery = @"
Resources
| where isnotempty(tags.CreatedBy) or isnotnull(tags.CreatedBy)
| project ResourceId = id
"@

$resultsSoFar = 0

do
{
    if($resultsSoFar -eq 0)
    {
        $result = Search-AzGraph -Query $argQuery -First $ARGPageSize -Subscription $Subscriptions
    } 
    else 
    {
        $result = Search-AzGraph -Query $argQuery -First $ARGPageSize -Skip $resultsSoFar -Subscription $Subscriptions
    }

    if ($result -and $result.GetType().Name -eq 'PSResourceGraphResponse')
    {
        $result = $result.data
    }

    $resultsCount = $result.Count
    $resultsSoFar += $resultsCount
    $ARGResults += $result
} while ( $resultsCount -eq $ARGPageSize )




$objStorageAccount = Get-AzStorageAccount -Name $storageAccountName -ResourceGroupName $resourceGroupName

$objContext = $objStorageAccount.Context

$objQueueMessages = @()

$invisibleTimeout = [System.TimeSpan]::FromSeconds(30)
$objQueue = Get-AzStorageQueue -Name $queueName -Context $objStorageAccount.Context

$counter = 0

Do {

    $continue = $true
    # Retrieve Message From Queue
    $objRawMessage = $objQueue.CloudQueue.GetMessageAsync($invisibleTimeout,$null,$null) 
    $objQueue.CloudQueue.DeleteMessageAsync($objRawMessage.Result.Id,$objRawMessage.Result.popReceipt)
    $objMessage = $objRawMessage.Result.AsString
    
    Try {
        $objMessage = $objMessage | ConvertFrom-Json -ErrorAction Stop
        $objQueue.CloudQueue.DeleteMessageAsync($objRawMessage.Result.Id,$objRawMessage.Result.popReceipt)
    } 
    Catch { 
        $continue = $false 
    }

    if (($continue -eq $true) -and -not !($ARGResults | % { Where-Object {$_.ResourceId -eq $objMessage.subject } })) 
    {
        Write-host "Continue False"
        Write-Host "object in ARG Results"
        #$objQueue.CloudQueue.GetMessageAsync($invisibleTimeout,$null,$null)
        #$objQueue.CloudQueue.DeleteMessageAsync($objRawMessage.Result.Id,$objRawMessage.Result.popReceipt)
        $continue = $false
    } elseif (-not !($taggedResources | % { Where-Object { $_.ResourceId -eq $objMessage.subject }}) ) {
        Write-host "Continue False"
        Write-Host "object in Tagged Results"
        #$objQueue.CloudQueue.GetMessageAsync($invisibleTimeout,$null,$null)
        #$objQueue.CloudQueue.DeleteMessageAsync($objRawMessage.Result.Id,$objRawMessage.Result.popReceipt)
        $continue = $false
    }


    if ($continue -eq $true)
    {
        Write-Host "Continue True"
        trap {
            if ((Get-AzContext).Subscription.Id -ne $objMessage.data.subscriptionId)
            {
                Get-AzSubscription -SubscriptionId $objMessage.data.subscriptionId -ErrorAction Stop | Set-AzContext
            }
        }

        if ($objMessage.data.authorization.evidence.principalType -eq 'ServicePrincipal')
        {
            try {
                $createdBy = (Get-AzADServicePrincipal -ObjectId $objMessage.data.authorization.evidence.principalId -ErrorAction Stop).DisplayName
            } catch {
                $createdBy = $objMessage.data.authorization.evidence.principalId
            }
        } else {

            if ( ($objMessage.data.claims.'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name') -and ($objMessage.data.claims.'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name' -match "[^@ \t\r\n]+@[^@ \t\r\n]+\.[^@ \t\r\n]+") ) {
                $createdBy = $objMessage.data.claims.'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name'
            } elseif ( ($objMessage.data.claims.'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/upn') -and ( $objMessage.data.claims.'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/upn' -match "[^@ \t\r\n]+@[^@ \t\r\n]+\.[^@ \t\r\n]+") ) {
                $createdBy = $objMessage.data.claims.'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/upn'
            } elseif ( ($objMessage.data.claims.'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress') -and ($objMessage.data.claims.'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress' -match "[^@ \t\r\n]+@[^@ \t\r\n]+\.[^@ \t\r\n]+") ) {
                $createdBy = $objMessage.data.claims.'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress'
            } else {
                $createdBy = $objMessage.data.claims.name
            }
        }
            Write-Host $createdBy

        try {
            $objTags = (Get-AzTag -ResourceId $objMessage.data.resourceUri -ErrorAction Stop).Properties.TagsProperty

            Write-Output "Resource Tags were retrieved"

            if ( $objTags.Count -eq 0 ) {
                Write-Output "Resource does not have any tags"
                Update-AzTag -Operation Merge -ResourceId $objMessage.data.resourceUri -Tag @{"$($CreatedByTagName)" = "$($createdBy)"} -ErrorAction Stop
                Write-Output "Resource was Tagged."
            } elseif ( !($objTags.Keys.Contains($CreatedByTagName)) ) {
                Write-Output "Resource does not have the $($CreatedByTagName) tag."
                Update-AzTag -Operation Merge -ResourceId $objMessage.data.resourceUri -Tag @{"$($CreatedByTagName)" = "$($createdBy)"} -ErrorAction Stop
                Write-Output "Resource was Tagged."
            } else {
                Write-Output "Tag exists"
            }

            $taggedResources += $objMessage.data.resourceUri
        } catch {
            Write-Error $_
        }
        $objRawMessage = $objQueue.CloudQueue.GetMessageAsync($invisibleTimeout,$null,$null)
    }

    # Counters
    $messagesInQueue = $objQueue.CloudQueue.ApproximateMessageCount
    $counter = $counter++

} Until (($counter -eq 10) -or ($messagesInQueue -eq 0))

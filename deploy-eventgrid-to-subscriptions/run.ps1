# Input bindings are passed in via param block.
param($Timer)

# Get the current universal time in the default string format
$currentUTCtime = (Get-Date).ToUniversalTime()

# The 'IsPastDue' porperty is 'true' when the current function invocation is later than scheduled.
if ($Timer.IsPastDue) {

    #region Set Variables
        #region Set Function Variables
        try {
            $function = (Get-AzResource -Name $env:WEBSITE_SITE_NAME -ErrorAction Stop)
            $function_SubscriptionId = $function.ResourceId.Split('/')[2]
            $function_ResourceGroupName = $function.ResourceGroupName
            $function_ResourceId = $function.ResourceId
            $function_Name = $function.Name
            $function_Endpoint_Name = 'set-resource-creator-tag'
        } catch {
            Write-Error "Failed to Get Azure Function to set Function Variables."
        }
        #endregion

        #region Set Tag Variables
        if (!($env:CREATED_BY_TAG_NAME)) { $CreatedByTagName = 'CreatedBy' } else { $CreatedByTagName = $env:CREATED_BY_TAG_NAME }
        if (!($env:CREATED_ON_DATE_TAG_NAME)) { $CreatedOnDateTagName = 'CreatedOnDate' } else { $CreatedOnDateTagName = $env:CREATED_ON_DATE_TAG_NAME }

        $objTags = $function.Tags
        if($objTags.ContainsKey("$($CreatedByTagName)")) { $tags["$($CreatedByTagName)"] = $function.Name }
        if ($objTags.ContainsKey("$($CreatedOnDateTagName)")) { $tags.Remove("$($CreatedOnDateTagName)") }
        #endregion

        #region Set Event Grid Variables
        if(!($env:EVENT_GRID_TOPIC_NAME) -or ($env:EVENT_GRID_TOPIC_NAME -eq '')) { $EVENT_GRID_TOPIC_NAME = '' } else { $EVENT_GRID_TOPIC_NAME = $env:EVENT_GRID_TOPIC_NAME }
        if(!($env:EVENT_GRID_RESOURCE_GROUP_NAME) -or ($env:EVENT_GRID_RESOURCE_GROUP_NAME = '')) { $EVENT_GRID_RESOURCE_GROUP_NAME = $function_ResourceGroupName } else { $EVENT_GRID_RESOURCE_GROUP_NAME = $env:EVENT_GRID_RESOURCE_GROUP_NAME }
        if(!($env:EVENT_GRID_LOCATION) -or ($env:EVENT_GRID_LOCATION = '')) { $EVENT_GRID_LOCATION = $function.Location } else { $EVENT_GRID_LOCATION = $env:EVENT_GRID_LOCATION }
        #endregion

        #region Script Variables
        $continue = $true
        $subscriptionExists = $false
        #endregion
    #endregion

    #region Main
    Get-AzSubscription | % {
        Try {
            Get-AzSubscription -SubscriptionId $_.SubscriptionId | Set-AzContext -ErrorAction Stop
        } Catch {
            Write-Error "Cannot authenticate to Subscription: $($_.Name)"
            break
        }

        #region Create Resource Group if it does not exist
        try {
            Get-AzResourceGroup -Name $EVENT_GRID_RESOURCE_GROUP_NAME -Location $EVENT_GRID_LOCATION -ErrorAction Stop
        } catch {
            try {
                New-AzResourceGroup -Name $EVENT_GRID_RESOURCE_GROUP_NAME -Location $EVENT_GRID_LOCATION -Tag $objTags -ErrorAction Stop
            } catch {
                Write-Error "Resource Group: $($EVENT_GRID_RESOURCE_GROUP_NAME) could not be created."
                $continue = $false
            }
        }
        #endregion

        #region Deploy Event Grid Topic if it does not exist
        if (($continue -eq $true) -and !(Get-AzResource | Where { $_.ResourceType -eq 'Microsoft.EventGrid/systemTopics' }))
        {
            try {
                # Test the availability of the ARM Template
                Invoke-RestMethod -Method Get -Uri $env:EVENT_GRID_TOPIC_TEMPLATE_URL -ErrorAction Stop

                $objParameters = @{
                    tags = $objTags
                }

                New-AzResourceGroupDeployment `
                    -ResourceGroupName $EVENT_GRID_RESOURCE_GROUP_NAME `
                    -TemplateUri $env:EVENT_GRID_TOPIC_TEMPLATE_URL `
                    -TemplateParameterObject $objTags `
                    -ErrorAction Stop
            } catch {
                Write-Error "Failed to create the Event Grid Topic"
            }
        } else {
            $objTopic = (Get-AzResource | Where { $_.ResourceType -eq 'Microsoft.EventGrid/systemTopics' })
        }
        #endregion

        #region Deploy Event Grid Subscription if it does not exist
        (Get-AzEventGridSubscription).PsEventSubscriptionsList | % { if ( $_.Endpoint -match $function_Name ) { $subscriptionExists = $true } }

        if (($continue -eq $true) -and ($subscriptionExists -eq $false))
        {
            if($EVENT_GRID_TOPIC_NAME -eq '') { $EVENT_GRID_TOPIC_NAME = $objTopic.Name }

            if($EVENT_GRID_RESOURCE_GROUP_NAME -ne $objTopic.ResourceGroupName) { $EVENT_GRID_RESOURCE_GROUP_NAME -eq $objTopic.ResourceGroupName }

            $objParameters = @{
                functionName = "$function_Name"
                function = "$function_Endpoint"
                eventGridTopicName = "$EVENT_GRID_TOPIC_NAME"
            }

            try {
                # Test the availability of the ARM Template
                Invoke-RestMethod -Method Get -Uri $env:EVENT_GRID_SUBSCRIPTION_TEMPLATE_URL -ErrorAction Stop

                New-AzResourceGroupDeployment `
                    -ResourceGroupName $EVENT_GRID_RESOURCE_GROUP_NAME `
                    -TemplateUri $env:EVENT_GRID_SUBSCRIPTION_TEMPLATE_URL `
                    -ErrorAction Stop
            } catch {
                Write-Error "Failed to create the Event Grid Subscription to the Azure Function"
            }

        }
        #endregion
    }
    #endregion
}

# Write an information log with the current time.
Write-Host "PowerShell timer trigger function ran! TIME: $currentUTCtime"

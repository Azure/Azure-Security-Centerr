$failureCount = 0
$successCount = 0
$vmSuccessCount = 0
$vmssSuccessCount = 0
$arcSuccessCount = 0
$vmCount = 0
$vmssCount = 0
$arcCount = 0
$vmResponseMachines = $null
$vmssResponseMachines = $null
$arcResponseMachines = $null
$outTable = @()

# Function to extract the desired part
function ExtractResourceGroupAndMachine {
    param (
        [string]$inputString
    )
    # Split the input string by '/'
    $parts = $inputString -split '/'
    
    # Find the indices of the desired parts
    $resourceGroupIndex = 4
    $machineIndex = 8
    
	try{
		return "$($parts[$resourceGroupIndex])/$($parts[$machineIndex])"
	}
	catch{
		return $null
	}    
}

# Function to add a row to the table
function AddRowToOutTable {
    param (
        [string]$simplifiedResourceId,
        [string]$resourceType,
        [string]$inherited,
        [string]$subPlan,
        [string]$pricingTier
    )
    $row = [PSCustomObject]@{
        ResourceId = $simplifiedResourceId
        ResourceType = $resourceType
        Inherited = $inherited
        SubPlan = $subPlan
        PricingTier = $pricingTier
    }
    #Write-Host "Adding row: $($simplifiedResourceId), $($resourceType), $($inherited), $($subPlan), $($pricingTier)" -ForegroundColor Gray
    $script:outTable += $row
}


# login:
$needLogin = $true
Try {
	$content = Get-AzContext
	if ($content)
	{
		$needLogin = ([string]::IsNullOrEmpty($content.Account))
	}
}
Catch
{
	if ($_ -like "*Login-AzAccount to login*")
	{
		$needLogin = $true
	}
	else
	{
		throw
	}
}

if ($needLogin)
{
	Write-Host -ForegroundColor "yellow" "Need to log in now! Look for login window!"
	Connect-Azaccount
}
# login - end

# get token
$accessToken = Get-AzAccessToken | Select-Object -ExpandProperty token
$expireson = Get-AzAccessToken | Select-Object -ExpandProperty expireson | Select-Object -ExpandProperty LocalDateTime

# Define variables for authentication and resource group
$SubscriptionId = Read-Host "Enter your SubscriptionId"
$mode = Read-Host "Enter 'RG' to read/set pricing for all resourced under a given Resource Group, or 'TAG' to read/set pricing for all resources with a given tagName and tagValue or 'ALL' to read/set pricing for all resources in the subscription"
while($mode.ToLower() -ne "rg" -and $mode.ToLower() -ne "tag" -and $mode.ToLower() -ne "all"){
	$mode = Read-Host "Enter 'RG' to read/set pricing for all resourced under a given Resource Group, or 'TAG' to read/set pricing for all resources with a given tagName and tagValue or 'ALL' to read/set pricing for all resources in the subscription"
}

if ($mode.ToLower() -eq "rg") {
    # Fetch resources under a given Resource Group
	$resourceGroupName = Read-Host "Enter the name of the resource group"
	try
	{
		# Get all virtual machines, VMSSs, and ARC machines in the resource group
		$vmUrl = "https://management.azure.com/subscriptions/" + $SubscriptionId + "/resourceGroups/$resourceGroupName/providers/Microsoft.Compute/virtualMachines?api-version=2021-04-01"
		do{
			$vmResponse = Invoke-RestMethod -Method Get -Uri $vmUrl -Headers @{Authorization = "Bearer $accessToken"}
			$vmResponseMachines += $vmResponse.value 
			$vmUrl = $vmResponse.nextLink
		} while (![string]::IsNullOrEmpty($vmUrl))

		$vmssUrl = "https://management.azure.com/subscriptions/" + $SubscriptionId + "/resourceGroups/$resourceGroupName/providers/Microsoft.Compute/virtualMachineScaleSets?api-version=2021-04-01"
		do{
			$vmssResponse = Invoke-RestMethod -Method Get -Uri $vmssUrl -Headers @{Authorization = "Bearer $accessToken"}
			$vmssResponseMachines += $vmssResponse.value
			$vmssUrl = $vmssResponse.nextLink
		} while (![string]::IsNullOrEmpty($vmssUrl))
		
		$arcUrl = "https://management.azure.com/subscriptions/" + $SubscriptionId + "/resourceGroups/$resourceGroupName/providers/Microsoft.HybridCompute/machines?api-version=2022-12-27"
		do{
			$arcResponse = Invoke-RestMethod -Method Get -Uri $arcUrl -Headers @{Authorization = "Bearer $accessToken"}
			$arcResponseMachines += $arcResponse.value
			write-host $arcUrl
			$arcUrl = $arcResponse.nextLink
		} while (![string]::IsNullOrEmpty($arcUrl))
	}
	catch 
	{
		Write-Host "Failed to Get resources! " -ForegroundColor Red
		Write-Host "Response StatusCode:" $_.Exception.Response.StatusCode.value__  -ForegroundColor Red
		Write-Host "Response StatusDescription:" $_.Exception.Response.StatusDescription -ForegroundColor Red
		Write-Host "Error from response:" $_.ErrorDetails -ForegroundColor Red
	}
} elseif ($mode.ToLower() -eq "tag") {
    # Fetch resources with a given tagName and tagValue
    $tagName = Read-Host "Enter the name of the tag"
    $tagValue = Read-Host "Enter the value of the tag"
	
	try
	{
		# Get all virtual machines, VMSSs, and ARC machines in the resource group based on the given tag
		$vmUrl = "https://management.azure.com/subscriptions/" + $SubscriptionId + "/resources?`$filter=resourceType eq 'Microsoft.Compute/virtualMachines'&api-version=2021-04-01"
		do{
			$vmResponse = Invoke-RestMethod -Method Get -Uri $vmUrl -Headers @{Authorization = "Bearer $accessToken"}
			$vmResponseMachines += $vmResponse.value | where {$_.tags.$tagName -eq $tagValue}
			$vmUrl = $vmResponse.nextLink
		} while (![string]::IsNullOrEmpty($vmUrl))
		
		$vmssUrl = "https://management.azure.com/subscriptions/" + $SubscriptionId + "/resources?`$filter=resourceType eq 'Microsoft.Compute/virtualMachineScaleSets'&api-version=2021-04-01"
		do{
			$vmssResponse = Invoke-RestMethod -Method Get -Uri $vmssUrl -Headers @{Authorization = "Bearer $accessToken"}
			$vmssResponseMachines += $vmssResponse.value | where {$_.tags.$tagName -eq $tagValue}
			$vmssUrl = $vmssResponse.nextLink
		} while (![string]::IsNullOrEmpty($vmssUrl))
		
		$arcUrl = "https://management.azure.com/subscriptions/" + $SubscriptionId + "/resources?`$filter=resourceType eq 'Microsoft.HybridCompute/machines'&api-version=2023-07-01"
		do{
			$arcResponse = Invoke-RestMethod -Method Get -Uri $arcUrl -Headers @{Authorization = "Bearer $accessToken"}
			$arcResponseMachines += $arcResponse.value | where {$_.tags.$tagName -eq $tagValue}
			$arcUrl = $arcResponse.nextLink
		} while (![string]::IsNullOrEmpty($arcUrl))
	}
	catch 
	{
		Write-Host "Failed to Get resources! " -ForegroundColor Red
		Write-Host "Response StatusCode:" $_.Exception.Response.StatusCode.value__  -ForegroundColor Red
		Write-Host "Response StatusDescription:" $_.Exception.Response.StatusDescription -ForegroundColor Red
		Write-Host "Error from response:" $_.ErrorDetails -ForegroundColor Red
	}
} elseif ($mode.ToLower() -eq "all") {	
	try
	{
		# Get all virtual machines, VMSSs, and ARC machines in the resource group based on the given tag
		$vmUrl = "https://management.azure.com/subscriptions/" + $SubscriptionId + "/resources?`$filter=resourceType eq 'Microsoft.Compute/virtualMachines'&api-version=2021-04-01"
		do{
			$vmResponse = Invoke-RestMethod -Method Get -Uri $vmUrl -Headers @{Authorization = "Bearer $accessToken"}
			$vmResponseMachines += $vmResponse.value 
			$vmUrl = $vmResponse.nextLink
		} while (![string]::IsNullOrEmpty($vmUrl))
		
		$vmssUrl = "https://management.azure.com/subscriptions/" + $SubscriptionId + "/resources?`$filter=resourceType eq 'Microsoft.Compute/virtualMachineScaleSets'&api-version=2021-04-01"
		do{
			$vmssResponse += Invoke-RestMethod -Method Get -Uri $vmssUrl -Headers @{Authorization = "Bearer $accessToken"}
			$vmssResponseMachines = $vmssResponse.value 
			$vmssUrl = $vmssResponse.nextLink
		} while (![string]::IsNullOrEmpty($vmssUrl))
		
		$arcUrl = "https://management.azure.com/subscriptions/" + $SubscriptionId + "/resources?`$filter=resourceType eq 'Microsoft.HybridCompute/machines'&api-version=2023-07-01"
		do{
			$arcResponse += Invoke-RestMethod -Method Get -Uri $arcUrl -Headers @{Authorization = "Bearer $accessToken"}
			$arcResponseMachines = $arcResponse.value 
			$arcUrl = $arcResponse.nextLink
		} while (![string]::IsNullOrEmpty($arcUrl))
	}
	catch 
	{
		Write-Host "Failed to Get resources! " -ForegroundColor Red
		Write-Host "Response StatusCode:" $_.Exception.Response.StatusCode.value__  -ForegroundColor Red
		Write-Host "Response StatusDescription:" $_.Exception.Response.StatusDescription -ForegroundColor Red
		Write-Host "Error from response:" $_.ErrorDetails -ForegroundColor Red
	}
} else {
    Write-Host "Entered invalid mode. Exiting script."
	exit 1;
}
# Finished fetching machines, display found machines:
Write-Host "Found the following resources:" -ForegroundColor Green
write-host "Virtual Machines:"
$count = 0
foreach ($machine in $vmResponseMachines) {
	$count++
	Write-Host $count ": " ($machine.name)
	$vmCount = $count
}
Write-Host "-------------------"
write-host "Virtual Machine Scale Sets:"
$count = 0
foreach ($machine in $vmssResponseMachines) {
	$count++
	Write-Host $count ": " ($machine.name)
	$vmssCount = $count
}
Write-Host "-------------------"
write-host "ARC Machines:"
$count = 0
foreach ($machine in $arcResponseMachines) {
	$count++
	Write-Host $count ": " ($machine.name)
	$arcCount = $count
}
Write-Host "-----------------------------------------------------------------------"
write-host "`n"

$continue = Read-Host "Press any key to proceed or press 'N' to exit"

if ($continue.ToLower() -eq "n") {
	exit 0
}

Write-Host "-------------------"
$InputCommand = Read-Host "Enter the command set these resources - 'Free' or 'Standard' or 'Revert' or 'Read' (choosing 'Free' will remove the Defender protection; 'Standard' will enable the 'P1' subplan; 'Revert' will remove any explicitly set configuration (the resource will inherit the parent's configuration); 'Read' will read the current configuration)"
while($InputCommand.ToLower() -ne "free" -and $InputCommand.ToLower() -ne "standard" -and $InputCommand.ToLower() -ne "revert" -and $InputCommand.ToLower() -ne "read"){
	$InputCommand = Read-Host "Enter the command for these resources - 'Free' or 'Standard' or 'Revert' or 'Read' (choosing 'Free' will remove the Defender protection; 'Standard' will enable the 'P1' subplan; 'Revert' will remove any explicitly set configuration (the resource will inherit the parent's configuration); 'Read' will read the current configuration)"
}

$saveToCsvPath = $null
$readCsvPath = $True

if ($InputCommand.ToLower() -eq "read") {
    while ($readCsvPath) {
        $saveToCsvPath = Read-Host "Path of the new or existing CSV file where the configuration should be exported. Leave blank if no export is required"
        
        if (-not [string]::IsNullOrEmpty($saveToCsvPath)) {
            if (Test-Path $saveToCsvPath) {
				# Path does exists
                if ((Get-Item $saveToCsvPath).PSIsContainer) {
                    # Path is a folder
                    Write-Host "Wrong path: please specify a path of a new or existing CSV file in an existing folder"
					$saveToCsvPath = $null
                } else {
                    # Path is a file
                    if ($saveToCsvPath -like "*.csv") {
                        # File is a CSV
                        $overwrite = Read-Host "The CSV file already exists. Do you want to overwrite it? (yes/no)"
                        if ($overwrite.ToLower() -eq "yes") {
                            $readCsvPath = $False
                        }
						else {
							$saveToCsvPath = $null
						}
                    } else {
                        # File is not a CSV
                        Write-Host "Wrong path: the specified file is not a CSV. Please enter the path of a new or existing CSV file"
						$saveToCsvPath = $null
                    }
                }
            } else {
                # Path does not exist
                if ((Get-Item (Split-Path $saveToCsvPath -Parent) -ErrorAction SilentlyContinue).PSIsContainer) {
                    # Parent folder exists
                    if ($saveToCsvPath -notlike "*.csv") {
                        Write-Host "Wrong path: the specified file is not a CSV file. Please enter the path of a new or existing CSV file"
						$saveToCsvPath = $null
                    }
					else{
						$readCsvPath = $False
					}
                } else {
                    # Parent folder does not exist
                    Write-Host "Wrong path: the specified path is in a non-existing folder. Please enter the path of a new or existing CSV file in an existing folder"
					$saveToCsvPath = $null
                } 
            }
        }
		else{
			$readCsvPath = $False
		}
    }
}

# Loop through each machine and update the pricing configuration
write-host "`n"
Write-Host "-------------------"
Write-Host "Processing (setting or reading) Virtual Machines:"
foreach ($machine in $vmResponseMachines) {
	# Check if need to renew the token	
    $currentTime = Get-Date
    
    Write-host "Token expires on: $expireson - currentTime: $currentTime"
    if ((get-date $currentTime) -ge (get-date $expireson)) {
		Start-Sleep -Seconds 2
        Write-host "Token expired - refreshing token:"
        $accessToken = Get-AzAccessToken | Select-Object -ExpandProperty token
        $expireson = Get-AzAccessToken | Select-Object -ExpandProperty expireson | Select-Object -ExpandProperty LocalDateTime

        Write-host "New token expires on: $expireson - currentTime: $currentTime - New Token is: $accessToken"
    }
	
    $pricingUrl = "https://management.azure.com$($machine.id)/providers/Microsoft.Security/pricings/virtualMachines?api-version=2024-01-01"
    if($InputCommand.ToLower() -eq "free")
	{
		$pricingBody = @{
			"properties" = @{
				"pricingTier" = "Free"
			}
		}
	} elseif($InputCommand.ToLower() -eq "standard")
	{
		$pricingBody = @{
			"properties" = @{
				"pricingTier" = "Standard"
				"subPlan" = "P1"
			}
		}
	}
	Write-Host "Processing (setting or reading) pricing configuration for '$($machine.name)':"
	try 
	{
		if($InputCommand.ToLower() -eq "revert")
		{
			$pricingResponse = Invoke-RestMethod -Method Delete -Uri $pricingUrl -Headers @{Authorization = "Bearer $accessToken"} -ContentType "application/json" -TimeoutSec 120
			Write-Host "Successfully reverted pricing configuration for $($machine.name)" -ForegroundColor Green
			$successCount++
			$vmSuccessCount++
		} elseif ($InputCommand.ToLower() -eq "read")
        {
            $pricingResponse = Invoke-RestMethod -Method Get -Uri $pricingUrl -Headers @{Authorization = "Bearer $accessToken"} -ContentType "application/json" -TimeoutSec 120
			Write-Host "Successfully read pricing configuration for $($machine.name): " -ForegroundColor Green
            Write-Host ($pricingResponse | ConvertTo-Json -Depth 100)
			try{
				$id = ExtractResourceGroupAndMachine -inputString $pricingResponse.id
				$name = $pricingResponse.name
				$inherited = $pricingResponse.properties.inherited 
				$subPlan = $pricingResponse.properties.subPlan
				$pricingTier = $pricingResponse.properties.pricingTier
				AddRowToOutTable -simplifiedResourceId $id -resourceType "VM" -inherited $inherited -subPlan $subPlan -pricingTier $pricingTier							
			}
			catch{
				Write-Host "Could not write a row in the results table for $($machine.name)" -ForegroundColor Yellow
				Write-Host "Exception caught: $($_.Exception.Message)" -ForegroundColor Yellow
  				Write-Host "Full Exception: $($_.Exception | Format-List -Force)" -ForegroundColor Yellow
			}
			$successCount++
			$vmSuccessCount++
        }
		else
		{
			$pricingResponse = Invoke-RestMethod -Method Put -Uri $pricingUrl -Headers @{Authorization = "Bearer $accessToken"} -Body ($pricingBody | ConvertTo-Json) -ContentType "application/json" -TimeoutSec 120
			Write-Host "Successfully updated pricing configuration for $($machine.name)" -ForegroundColor Green
			$successCount++
			$vmSuccessCount++
		}
	}
	catch {
		$failureCount++
		Write-Host "Failed to process (set or read) pricing configuration for $($machine.name)" -ForegroundColor Red
		Write-Host "Response StatusCode:" $_.Exception.Response.StatusCode.value__  -ForegroundColor Red
		Write-Host "Response StatusDescription:" $_.Exception.Response.StatusDescription -ForegroundColor Red
		Write-Host "Error from response:" $_.ErrorDetails -ForegroundColor Red
	}
	write-host "`n"
	Start-Sleep -Seconds 0.3
}

Write-Host "-------------------"
Write-Host "Processing (setting or reading) Virtual Machine Scale Sets:"
foreach ($machine in $vmssResponseMachines) {
	# Check if need to renew the token
    $currentTime = Get-Date
    
    Write-host "Token expires on: $expireson - currentTime: $currentTime"
    if ((get-date $currentTime) -ge (get-date $expireson)) {
		Start-Sleep -Seconds 2
        Write-host "Token expired - refreshing token:"
        $accessToken = Get-AzAccessToken | Select-Object -ExpandProperty token
        $expireson = Get-AzAccessToken | Select-Object -ExpandProperty expireson | Select-Object -ExpandProperty LocalDateTime

        Write-host "New token expires on: $expireson - currentTime: $currentTime - New Token is: $accessToken"
    }
	
    $pricingUrl = "https://management.azure.com$($machine.id)/providers/Microsoft.Security/pricings/virtualMachines?api-version=2024-01-01"
    if($InputCommand.ToLower() -eq "free")
	{
		$pricingBody = @{
			"properties" = @{
				"pricingTier" = "Free"
			}
		}
	} elseif($InputCommand.ToLower() -eq "standard")
	{
		$pricingBody = @{
			"properties" = @{
				"pricingTier" = "Standard"
				"subPlan" = "P1"
			}
		}
	}
	Write-Host "Processing (setting or reading) pricing configuration for '$($machine.name)':"
	try 
	{
		
		if($InputCommand.ToLower() -eq "revert")
		{
			$pricingResponse = Invoke-RestMethod -Method Delete -Uri $pricingUrl -Headers @{Authorization = "Bearer $accessToken"} -ContentType "application/json" -TimeoutSec 120
			Write-Host "Successfully reverted pricing configuration for $($machine.name)" -ForegroundColor Green
			$successCount++
			$vmssSuccessCount++
		} elseif ($InputCommand.ToLower() -eq "read")
        {
            $pricingResponse = Invoke-RestMethod -Method Get -Uri $pricingUrl -Headers @{Authorization = "Bearer $accessToken"} -ContentType "application/json" -TimeoutSec 120
			Write-Host "Successfully read pricing configuration for $($machine.name): " -ForegroundColor Green
            Write-Host ($pricingResponse | ConvertTo-Json -Depth 100)
			try{
				$id = ExtractResourceGroupAndMachine -inputString $pricingResponse.id
				$name = $pricingResponse.name
				$inherited = $pricingResponse.properties.inherited 
				$subPlan = $pricingResponse.properties.subPlan
				$pricingTier = $pricingResponse.properties.pricingTier
				AddRowToOutTable -simplifiedResourceId $id -resourceType "VMSS Machine" -inherited $inherited -subPlan $subPlan -pricingTier $pricingTier							
			}
			catch{
				Write-Host "Could not write a row in the results table for $($machine.name)" -ForegroundColor Yellow
				Write-Host "Exception caught: $($_.Exception.Message)" -ForegroundColor Yellow
  				Write-Host "Full Exception: $($_.Exception | Format-List -Force)" -ForegroundColor Yellow
			}			
			$successCount++
			$vmssSuccessCount++
        }
		else
		{
            $pricingResponse = Invoke-RestMethod -Method Put -Uri $pricingUrl -Headers @{Authorization = "Bearer $accessToken"} -Body ($pricingBody | ConvertTo-Json) -ContentType "application/json" -TimeoutSec 120
            Write-Host "Successfully updated pricing configuration for $($machine.name)" -ForegroundColor Green
            $successCount++
            $vmssSuccessCount++
        }
	}
	catch {
		$failureCount++
		Write-Host "Failed to process (set or read) pricing configuration for $($machine.name)" -ForegroundColor Red
		Write-Host "Response StatusCode:" $_.Exception.Response.StatusCode.value__  -ForegroundColor Red
		Write-Host "Response StatusDescription:" $_.Exception.Response.StatusDescription -ForegroundColor Red
		Write-Host "Error from response:" $_.ErrorDetails -ForegroundColor Red
	}
	write-host "`n"
	Start-Sleep -Seconds 0.3
}

Write-Host "-------------------"
Write-Host "Processing (setting or reading) ARC Machine:"
foreach ($machine in $arcResponseMachines) {
	# Check if need to renew the token
    $currentTime = Get-Date
    
    Write-host "Token expires on: $expireson - currentTime: $currentTime"
    if ((get-date $currentTime) -ge (get-date $expireson)) {
		Start-Sleep -Seconds 2
        Write-host "Token expired - refreshing token:"
        $accessToken = Get-AzAccessToken | Select-Object -ExpandProperty token
        $expireson = Get-AzAccessToken | Select-Object -ExpandProperty expireson | Select-Object -ExpandProperty LocalDateTime

        Write-host "New token expires on: $expireson - currentTime: $currentTime - New Token is: $accessToken"
    }
	
    $pricingUrl = "https://management.azure.com$($machine.id)/providers/Microsoft.Security/pricings/virtualMachines?api-version=2024-01-01"
    if($InputCommand.ToLower() -eq "free")
	{
		$pricingBody = @{
			"properties" = @{
				"pricingTier" = "Free"
			}
		}
	} elseif($InputCommand.ToLower() -eq "standard")
	{
		$pricingBody = @{
			"properties" = @{
				"pricingTier" = "Standard"
				"subPlan" = "P1"
			}
		}
	}
	Write-Host "Processing (setting or reading) pricing configuration for '$($machine.name)':"
	try 
	{
		
		if($InputCommand.ToLower() -eq "revert")
		{
			$pricingResponse = Invoke-RestMethod -Method Delete -Uri $pricingUrl -Headers @{Authorization = "Bearer $accessToken"} -ContentType "application/json" -TimeoutSec 120
			Write-Host "Successfully reverted pricing configuration for $($machine.name)" -ForegroundColor Green
			$successCount++
			$arcSuccessCount++
		} elseif ($InputCommand.ToLower() -eq "read")
        {
            $pricingResponse = Invoke-RestMethod -Method Get -Uri $pricingUrl -Headers @{Authorization = "Bearer $accessToken"} -ContentType "application/json" -TimeoutSec 120
			Write-Host "Successfully read pricing configuration for $($machine.name): " -ForegroundColor Green
            Write-Host ($pricingResponse | ConvertTo-Json -Depth 100)
			try{
				$id = ExtractResourceGroupAndMachine -inputString $pricingResponse.id
				$name = $pricingResponse.name
				$inherited = $pricingResponse.properties.inherited 
				$subPlan = $pricingResponse.properties.subPlan
				$pricingTier = $pricingResponse.properties.pricingTier
				AddRowToOutTable -simplifiedResourceId $id -resourceType "Arc Machine" -inherited $inherited -subPlan $subPlan -pricingTier $pricingTier							
			}
			catch{
				Write-Host "Could not write a row in the results table for $($machine.name)" -ForegroundColor Yellow
				Write-Host "Exception caught: $($_.Exception.Message)" -ForegroundColor Yellow
  				Write-Host "Full Exception: $($_.Exception | Format-List -Force)" -ForegroundColor Yellow
			}
			$successCount++
			$arcSuccessCount++
        }
		else
		{
            $pricingResponse = Invoke-RestMethod -Method Put -Uri $pricingUrl -Headers @{Authorization = "Bearer $accessToken"} -Body ($pricingBody | ConvertTo-Json) -ContentType "application/json" -TimeoutSec 120
            Write-Host "Successfully updated pricing configuration for $($machine.name)" -ForegroundColor Green
            $successCount++
            $arcSuccessCount++
        }
	}
	catch {
		$failureCount++
		Write-Host "Failed to process (set or read) pricing configuration for $($machine.name)" -ForegroundColor Red
		Write-Host "Response StatusCode:" $_.Exception.Response.StatusCode.value__  -ForegroundColor Red
		Write-Host "Response StatusDescription:" $_.Exception.Response.StatusDescription -ForegroundColor Red
		Write-Host "Error from response:" $_.ErrorDetails -ForegroundColor Red
	}
	write-host "`n"
	Start-Sleep -Seconds 0.3
}


Write-Host "-----------------------------------------------------------------------"
Write-Host "-----------------------------------------------------------------------"
write-host "`n"
# Write a conclusion of all what the script did
Write-Host "Summary of Pricing API results:"
Write-Host "-------------------"
Write-Host "Found Virtual Machines count:" $vmCount
Write-Host "Successfully processed (set or read) Virtual Machines count:" $vmSuccessCount -ForegroundColor Green
Write-Host "Failed processing (setting or reading) Virtual Machines count:" $($vmCount - $vmSuccessCount) -ForegroundColor $(if ($($vmCount - $vmSuccessCount) -gt 0) {'Red'} else {'Green'})
write-host "`n"
Write-Host "Found Virtual Machine Scale Sets count:" $vmssCount
Write-Host "Successfully processed (set or read) Virtual Machine Scale Sets result:" $vmssSuccessCount -ForegroundColor Green
Write-Host "Failed processing (setting or reading) Virtual Machine Scale Sets count:" $($vmssCount - $vmssSuccessCount) -ForegroundColor $(if ($($vmssCount - $vmssSuccessCount) -gt 0) {'Red'} else {'Green'})
write-host "`n"
Write-Host "Found ARC machines count:" $arcCount
Write-Host "Successfully processed (set or read) ARC Machines count:" $arcSuccessCount -ForegroundColor Green
Write-Host "Failed processing (setting or reading) ARC Machines count:" $($arcCount - $arcSuccessCount) -ForegroundColor $(if ($($arcCount - $arcSuccessCount) -gt 0) {'Red'} else {'Green'})
write-host "`n"
Write-Host "-------------------"
Write-Host "Overall"
Write-Host "Successfully processed (set or read) resources: $successCount" -ForegroundColor Green
Write-Host "Failures processing (setting or reading) resources: $failureCount" -ForegroundColor $(if ($failureCount -gt 0) {'Red'} else {'Green'})

if($InputCommand.ToLower() -eq "read"){
	$outTable  | Format-Table -AutoSize

	if(-not [string]::IsNullOrEmpty($saveToCsvPath)){
		$outTable | Export-Csv -Path $saveToCsvPath -NoTypeInformation
		Write-Host "CSV file ready:" $saveToCsvPath -ForegroundColor Green
	}
}

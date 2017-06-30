
#region -----------------ReadMe------------------------
<#
Questions or Issues: Email mike.kassis@microsoft.com

Readme:
    This module is meant to make it easy to pull and set information in Azure Security Center. Until I change the way authentication works, it is 
    recommended to use AzureRM module 2.2.0 to avoid errors. This will change in the future.

    The Azure Security Center API's are currently being updated, which could cause future issues with this module. I will update this module
    as soon as possible once these new endpoint versions are released. 

    This is a community supported project, and not part of the official AzureRM module or the Azure Security Center product. There is no
    warranty of any kind around this module. Use at your own risk.

    The global variables section below should not need to be changed, however, note that $asc_subscriptionid can be set by providing a new 
    Azure subscription ID from your tenant in your currently authenticated session. You can loop through your subscriptions in a tenant by
    setting the $asc_subscriptionid variable with your desired subscription ID. You cannot provide subscription ID's from a different tenant unless
    you have run Login-ASC again and authenticated to that tenant.

    Example of looping through subscriptions to retrieve the default policy for each:

    (Get-AzureRmSubscription).subscriptionId | foreach {
        Set-Variable -Name asc_subscriptionId -Value $_ -Scope Global 
        Get-ASCPolicy -PolicyName default }
#>
#endregion

#region ------------Script Variables-------------------
function Set-ASCVars {
    $Script:asc_clientId = "1950a258-227b-4e31-a9cf-717495945fc2"              # Well-known client ID for Azure PowerShell
    $Script:asc_redirectUri = "urn:ietf:wg:oauth:2.0:oob"                      # Redirect URI for Azure PowerShell
    $Script:asc_resourceAppIdURI = "https://management.azure.com/"             # Resource URI for REST API
    $Script:asc_url = 'management.azure.com'                                   # Well-known URL endpoint
    $Script:asc_version = "2015-06-01-preview"                                 # Latest API version
    $Script:version = $asc_version
    }
#endregion

#region -----------------Cmdlets-----------------------
#region ASC Credentials

function Set-ASCAuth {
    [CmdletBinding()]
    Param
    (
    )
    Begin
    {
    if(-not (Get-Module AzureRm.Profile)) {
        Import-Module AzureRm.Profile
        }
        
    $azureRmProfileModuleVersion = (Get-Module AzureRm.Profile).Version
    
        # refactoring performed in AzureRm.Profile v3.0 or later
    if($azureRmProfileModuleVersion.Major -ge 3) {
        $azureRmProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile
        if(-not $azureRmProfile.Accounts.Count) {
            Write-Error "Ensure you have logged in before calling this function."    
        }
    } 
    
    else {
        # AzureRm.Profile < v3.0
        $azureRmProfile = [Microsoft.WindowsAzure.Commands.Common.AzureRmProfileProvider]::Instance.Profile
        if(-not $azureRmProfile.Context.Account.Count) {
        Write-Error "Ensure you have logged in before calling this function."    
        }
    }

    $currentAzureContext = Get-AzureRmContext
    $profileClient = New-Object Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient($azureRmProfile)
    Write-Debug ("Getting access token for tenant" + $currentAzureContext.Subscription.TenantId)
    $token = $profileClient.AcquireAccessToken($currentAzureContext.Subscription.TenantId)
    $token = $token.AccessToken
    $asc_subscriptionId = $currentAzureContext.Subscription.Id
    $asc_tenantId = $currentAzureContext.Tenant.Id
    Set-Variable -Name asc_requestHeader -Scope Script -Value @{"Authorization" = "Bearer $token"}   
    #2.x AzureRM outputs subscriptionid differently.
    if($azureRmProfileModuleVersion.Major -le 2) {Set-Variable -Name asc_subscriptionId -Scope Script -Value $currentAzureContext.Subscription.SubscriptionId}
    else{Set-Variable -Name asc_subscriptionId -Scope Script -Value $currentAzureContext.Subscription.Id}
    }

}

#endregion
#region ASC JSON
<#
.Synopsis
   Build-ASCJSON creates the JSON format needed for Set-ASCPolicy.
.DESCRIPTION
   When running the command, it will perform a GET request for your existing ASC policy configuraiton and will only update parameters you specify. The command currently has parameters for JIT Port Administration configuration, but the JIT commands are not currently in the module. These will be added later.
.EXAMPLE
   Build-ASCJSON -Type Policy -PolicyName Default

{
    "properties":  {
                       "policyLevel":  "Subscription",
                       "name":  "default",
                       "unique":  "Off",
                       "logCollection":  "On",
                       "recommendations":  {
                                               "patch":  "On",
                                               "baseline":  "On",
                                               "antimalware":  "On",
                                               "diskEncryption":  "On",
                                               "acls":  "On",
                                               "nsgs":  "On",
                                               "waf":  "On",
                                               "sqlAuditing":  "On",
                                               "sqlTde":  "On",
                                               "ngfw":  "On",
                                               "vulnerabilityAssessment":  "On",
                                               "storageEncryption":  "On",
                                               "jitNetworkAccess":  "On"
                                           },
                       "logsConfiguration":  {
                                                 "storages":  {

                                                              }
                                             },
                       "omsWorkspaceConfiguration":  {
                                                         "workspaces":  {

                                                                        }
                                                     },
                       "securityContactConfiguration":  {
                                                            "securityContactEmails":  [
                                                                                          "mike.kassis@microsoft.com",
                                                                                          "hello@world.com"
                                                                                      ],
                                                            "securityContactPhone":  "867-5309",
                                                            "areNotificationsOn":  true,
                                                            "sendToAdminOn":  false
                                                        },
                       "pricingConfiguration":  {
                                                    "selectedPricingTier":  "Free",
                                                    "standardTierStartDate":  "0001-01-01T00:00:00",
                                                    "premiumTierStartDate":  "0001-01-01T00:00:00"
                                                },
                       "lastStorageCreationTime":  "1970-01-01T00:00:00Z"
                   }
}

    The above example simply shows the existing configuration for the specified policy.

.EXAMPLE
   Build-ASCJSON -Type Policy -PolicyName Default -AllOff -LogCollection Off -SecurityContactEmail "bin@bash.com","bash@bin.com"

{
    "properties":  {
                       "policyLevel":  "Subscription",
                       "name":  "default",
                       "unique":  "Off",
                       "logCollection":  "Off",
                       "recommendations":  {
                                               "patch":  "Off",
                                               "baseline":  "Off",
                                               "antimalware":  "Off",
                                               "diskEncryption":  "Off",
                                               "acls":  "Off",
                                               "nsgs":  "Off",
                                               "waf":  "Off",
                                               "sqlAuditing":  "Off",
                                               "sqlTde":  "Off",
                                               "ngfw":  "Off",
                                               "vulnerabilityAssessment":  "Off",
                                               "storageEncryption":  "Off",
                                               "jitNetworkAccess":  "Off"
                                           },
                       "logsConfiguration":  {
                                                 "storages":  {

                                                              }
                                             },
                       "omsWorkspaceConfiguration":  {
                                                         "workspaces":  {

                                                                        }
                                                     },
                       "securityContactConfiguration":  {
                                                            "securityContactEmails":  [
                                                                                          "bin@bash.com",
                                                                                          "bash@bin.com"
                                                                                      ],
                                                            "securityContactPhone":  "867-5309",
                                                            "areNotificationsOn":  true,
                                                            "sendToAdminOn":  false
                                                        },
                       "pricingConfiguration":  {
                                                    "selectedPricingTier":  "Free",
                                                    "standardTierStartDate":  "0001-01-01T00:00:00",
                                                    "premiumTierStartDate":  "0001-01-01T00:00:00"
                                                },
                       "lastStorageCreationTime":  "1970-01-01T00:00:00Z"
                   }
}

    The above example builds a policy that turns all recommendations off and log collection off and changes the security contact to "bin@bash.com" and "bash@bin.com"


#>
function Build-ASCJSON
{
    [CmdletBinding()]
    Param
    (
        # Type - Specify type of JSON config to build.
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$false,
                   ParameterSetName='Policy')]
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$false,
                   ParameterSetName='ProtectedResource')]
        [ValidateSet('Policy','ProtectedResource')]
        [string]$Type, 

        # PolicyName - Specify policy name for configuration.Note: Currently only Default is supported for Policy configurations.
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$false,
                   ParameterSetName='Policy')]
        [string]$PolicyName, 

        # Security Contact Email. You may specify multiple names by comma separating. Example: "foo@bar.com", "hello@world.com"
        [Parameter(Mandatory=$false,
                   ValueFromPipelineByPropertyName=$false,
                   ParameterSetName='Policy')]
        [string[]]$SecurityContactEmail,   

        # Security Contact Phone Number.
        [Parameter(Mandatory=$false,
                   ValueFromPipelineByPropertyName=$false,
                   ParameterSetName='Policy')]
        [string]$SecurityContactPhone, 

        # Security Contact - Send notifications about alerts. This turns on automated notifications for the subscription.
        [Parameter(Mandatory=$false,
                   ValueFromPipelineByPropertyName=$false,
                   ParameterSetName='Policy')]
        [ValidateSet('true','false')]
        [string]$SecurityContactNotificationsOn, 

        # Security Contact - Send notifications to subscription owner as well.
        [Parameter(Mandatory=$false,
                   ValueFromPipelineByPropertyName=$false,
                   ParameterSetName='Policy')]
        [ValidateSet('true','false')]
        [string]$SecurityContactSendToAdminOn, 

        # All Recommendations On. This turns all ASC recommendation flags to 'On'.
        [Parameter(Mandatory=$false,
                   ValueFromPipelineByPropertyName=$false,
                   ParameterSetName='Policy')]
        [switch]$AllOn, 

        # All Recommendations Off. This turns all ASC recommendation flags to 'Off'.
        [Parameter(Mandatory=$false,
                   ValueFromPipelineByPropertyName=$false,
                   ParameterSetName='Policy')]
        [switch]$AllOff, 

        # Patch. Specifies if Patch recommendation should be 'On' or 'Off'.
        [Parameter(Mandatory=$false,
                   ValueFromPipelineByPropertyName=$false,
                   ParameterSetName='Policy')]
        [ValidateSet('On','Off')]
        [string]$Patch,       
        
        # Baseline. Specifies if Baseline recommendation should be 'On' or 'Off'.
        [Parameter(Mandatory=$false,
                   ValueFromPipelineByPropertyName=$false,
                   ParameterSetName='Policy')]
        [ValidateSet('On','Off')]
        [string]$Baseline,   

        # AntiMalware. Specifies if AntiMalware recommendation should be 'On' or 'Off'.
        [Parameter(Mandatory=$false,
                   ValueFromPipelineByPropertyName=$false,
                   ParameterSetName='Policy')]
        [ValidateSet('On','Off')]
        [string]$AntiMalware, 

        # DiskEncryption. Specifies if DiskEncryption recommendation should be 'On' or 'Off'.
        [Parameter(Mandatory=$false,
                   ValueFromPipelineByPropertyName=$false,
                   ParameterSetName='Policy')]
        [ValidateSet('On','Off')]
        [string]$DiskEncryption, 

        # ACLS. Specifies if ACLS recommendation should be 'On' or 'Off'.
        [Parameter(Mandatory=$false,
                   ValueFromPipelineByPropertyName=$false,
                   ParameterSetName='Policy')]
        [ValidateSet('On','Off')]
        [string]$ACLS, 

        # NSGS. Specifies if NSGS recommendation should be 'On' or 'Off'.
        [Parameter(Mandatory=$false,
                   ValueFromPipelineByPropertyName=$false,
                   ParameterSetName='Policy')]
        [ValidateSet('On','Off')]
        [string]$NSGS, 

        # WAF. Specifies if WAF recommendation should be 'On' or 'Off'.
        [Parameter(Mandatory=$false,
                   ValueFromPipelineByPropertyName=$false,
                   ParameterSetName='Policy')]
        [ValidateSet('On','Off')]
        [string]$WAF, 

        # SQLAuditing. Specifies if SQL Auditing recommendation should be 'On' or 'Off'.
        [Parameter(Mandatory=$false,
                   ValueFromPipelineByPropertyName=$false,
                   ParameterSetName='Policy')]
        [ValidateSet('On','Off')]
        [string]$SQLAuditing, 

        # SQLTDE. Specifies if SQLTDE recommendation should be 'On' or 'Off'.
        [Parameter(Mandatory=$false,
                   ValueFromPipelineByPropertyName=$false,
                   ParameterSetName='Policy')]
        [ValidateSet('On','Off')]
        [string]$SQLTDE, 

        # NGFW. Specifies if NGFW recommendation should be 'On' or 'Off'.
        [Parameter(Mandatory=$false,
                   ValueFromPipelineByPropertyName=$false,
                   ParameterSetName='Policy')]
        [ValidateSet('On','Off')]
        [string]$NGFW, 

        # VulnerabilityAssessment. Specifies if Vulnerability Assessment recommendation should be 'On' or 'Off'.
        [Parameter(Mandatory=$false,
                   ValueFromPipelineByPropertyName=$false,
                   ParameterSetName='Policy')]
        [ValidateSet('On','Off')]
        [string]$VulnerabilityAssessment, 

        # StorageEncryption. Specifies if Storage Encryption recommendation should be 'On' or 'Off'.
        [Parameter(Mandatory=$false,
                   ValueFromPipelineByPropertyName=$false,
                   ParameterSetName='Policy')]
        [ValidateSet('On','Off')]
        [string]$StorageEncryption, 

        # JITNetworkAccess. Specifies if JIT Network Access recommendation should be 'On' or 'Off'.
        [Parameter(Mandatory=$false,
                   ValueFromPipelineByPropertyName=$false,
                   ParameterSetName='Policy')]
        [ValidateSet('On','Off')]
        [string]$JITNetworkAccess, 
        
        # DataCollection. Specifies if data collection for the resources in the subscription should be 'On' or 'Off'.
        [Parameter(Mandatory=$false,
                   ValueFromPipelineByPropertyName=$false,
                   ParameterSetName='Policy')]
        [ValidateSet('On','Off')]
        [string]$DataCollection, 

        # Pricing Tier. Specifies the pricing tier for the subscription. Note, setting this to Standard may cause you to incur costs.
        [Parameter(Mandatory=$false,
                   ValueFromPipelineByPropertyName=$false,
                   ParameterSetName='Policy')]
        [ValidateSet('Free','StandardTrial','Standard')]
        [string]$PricingTier, 

        # ResourceGroupName
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$false,
                   ParameterSetName='ProtectedResource')]
        [string]$ResourceGroupName, 

        # SolutionName
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$false,
                   ParameterSetName='ProtectedResource')]
        [ValidateSet('Qualys')]
        [string]$SolutionName, 

        # ResourceAzureId
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$false,
                   ParameterSetName='ProtectedResource')]
        [string]$ResourceAzureId, 

        # TaskId
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$false,
                   ParameterSetName='ProtectedResource')]
        [string]$TaskId, 

        # Security API version. By default this uses the $asc_version variable which this module pre-sets. Only specify this if necessary.
        [Parameter(Mandatory=$false)]
        [string]$Version = $asc_version
    )

    Begin
    {
        Set-ASCVars
        Set-ASCAuth
        try{
        # Additional parameter validations and mutual exclusions
        If ($AllOn -and $AllOff) {Throw 'Cannot reconcile app parameters. Only use one of them at a time.'}
        If (($AllOn -or $AllOff) -and ($Patch -or $Baseline -or $AntiMalware -or $DiskEncryption -or $ACLS -or $NSGS -or $WAF -or $SQLAuditing -or $SQLTDE -or $NGFW -or $VulnerabilityAssessment -or $StorageEncryption -or $JITNetworkAccess)) {Throw 'Cannot reconcile app parameters. Do not specify individual properties in addition to AllOn or AllOf.'}


        if ($Type -eq 'Policy') {
           
            #Retrieve existing policy and build hashtable
            $a = Get-ASCPolicy -PolicyName $PolicyName
            $json_policy = @{
            properties = @{
            policyLevel = $a.properties.policyLevel
            policyName = $a.properties.name
            unique = $a.properties.unique
            logCollection = $a.properties.logCollection
            recommendations = $a.properties.recommendations
            logsConfiguration = $a.properties.logsConfiguration
            omsWorkspaceConfiguration = $a.properties.omsWorkspaceConfiguration
            securityContactConfiguration = $a.properties.securityContactConfiguration
            pricingConfiguration = $a.properties.pricingConfiguration
            }
            }

            if ($json_policy.properties.recommendations -eq $null){Write-Error "The specified policy does not exist."; return}

            #Turn all recommendations off if specified
            if ($AllOff){

                #Set all params to off unless specified
                $json_policy.properties.recommendations.patch =                    "Off"
                $json_policy.properties.recommendations.baseline =                 "Off"
                $json_policy.properties.recommendations.antimalware =              "Off"
                $json_policy.properties.recommendations.diskEncryption =           "Off"
                $json_policy.properties.recommendations.acls =                     "Off"
                $json_policy.properties.recommendations.nsgs =                     "Off"
                $json_policy.properties.recommendations.waf =                      "Off"
                $json_policy.properties.recommendations.sqlAuditing =              "Off"
                $json_policy.properties.recommendations.sqlTde =                   "Off"
                $json_policy.properties.recommendations.ngfw =                     "Off"
                $json_policy.properties.recommendations.vulnerabilityAssessment =  "Off"
                $json_policy.properties.recommendations.storageEncryption =        "Off"
                $json_policy.properties.recommendations.jitNetworkAccess =         "Off"
                }
    
            #Turn all recommendations on if specified
            if ($AllOn){

                #Set all params to off unless specified
                $json_policy.properties.recommendations.patch =                    "On"
                $json_policy.properties.recommendations.baseline =                 "On"
                $json_policy.properties.recommendations.antimalware =              "On"
                $json_policy.properties.recommendations.diskEncryption =           "On"
                $json_policy.properties.recommendations.acls =                     "On"
                $json_policy.properties.recommendations.nsgs =                     "On"
                $json_policy.properties.recommendations.waf =                      "On"
                $json_policy.properties.recommendations.sqlAuditing =              "On"
                $json_policy.properties.recommendations.sqlTde =                   "On"
                $json_policy.properties.recommendations.ngfw =                     "On"
                $json_policy.properties.recommendations.vulnerabilityAssessment =  "On"
                $json_policy.properties.recommendations.storageEncryption =        "On"
                $json_policy.properties.recommendations.jitNetworkAccess =         "On"
                }

            #Update recommendations if individual parameters are specified
            If ($Patch){$json_policy.properties.recommendations.patch = $Patch}
            If ($Baseline){$json_policy.properties.recommendations.baseline = $Baseline}
            If ($AntiMalware){$json_policy.properties.recommendations.antimalware = $AntiMalware}
            If ($DiskEncryption){$json_policy.properties.recommendations.diskEncryption = $DiskEncryption}
            If ($ACLS){$json_policy.properties.recommendations.acls = $ACLS}
            If ($NSGS){$json_policy.properties.recommendations.nsgs = $NSGS}
            If ($WAF){$json_policy.properties.recommendations.waf = $WAF}
            If ($SQLAuditing){$json_policy.properties.recommendations.sqlAuditing = $SQLAuditing}
            If ($SQLTDE){$json_policy.properties.recommendations.sqlTde = $SQLTDE}
            If ($NGFW){$json_policy.properties.recommendations.ngfw = $NGFW}
            If ($VulnerabilityAssessment){$json_policy.properties.recommendations.vulnerabilityAssessment = $VulnerabilityAssessment}
            If ($StorageEncryption){$json_policy.properties.recommendations = $StorageEncryption}
            If ($JITNetworkAccess){$json_policy.properties.recommendations.jitNetworkAccess = $JITNetworkAccess}

            #Update security contact information if specified
            If ($SecurityContactEmail){
                $SecurityContactEmailArray = @()
                foreach ($i in $SecurityContactEmail){$SecurityContactEmailArray += $i}
                $json_policy.properties.securityContactConfiguration.securityContactEmails = $SecurityContactEmailArray}
                
            If ($SecurityContactPhone){$json_policy.properties.securityContactConfiguration.securityContactPhone = $SecurityContactPhone}
            If ($SecurityContactNotificationsOn){$json_policy.properties.securityContactConfiguration.areNotificationsOn = $SecurityContactNotificationsOn}
            If ($SecurityContactSendToAdminOn){$json_policy.properties.securityContactConfiguration.sendToAdminOn = $SecurityContactSendToAdminOn} 
            #If ($SecurityContactEmail -or $SecurityContactPhone -or $SecurityContactNotifications -or $SecurityContactSendToAdmin) {$json_policy.properties.securityContactConfiguration.lastSaveDateTime = ((get-date -Format o) -replace '-\d{2}:\d{2}','Z')}

            #Update data collection if specified
            If ($DataCollection){$json_policy.properties.logCollection = $DataCollection}

            #Update pricing tier if specified
            If ($PricingTier){$json_policy.properties.pricingConfiguration.selectedPricingTier = $PricingTier}

            #Convert hash table to JSON for Set-ASCPolicy cmdlet
            $json_policy | ConvertTo-Json -Depth 3
                    }
 
         if ($Type -eq 'ProtectedResource') {
  
            $json_policy = @{
            resourceAzureId = $ResourceAzureId
            taskId = $TaskId
            }
            
         }
    
     }#end try block

     catch{
        Write-Error $_
     }
    }#end begin block
    Process
    {
    }
    End
    {
    }
}
#endregion
#region ASC Policies
<#
.Synopsis
   Get-ASCPolicy
.DESCRIPTION
   Get-ASCPolicy is used to retrieve either a list of set policies or a specific policy for a specified resource.
.EXAMPLE
   Get-ASCPolicy | Format-List


    id         : /subscriptions/<subscriptionId>/providers/Microsoft.Security/policies/policy1
    name       : default
    type       : Microsoft.Security/policies
    properties : @{policyLevel=Subscription; name=Default; unique=Off; logCollection=On; recommendations=; logsConfiguration=; omsWorkspaceConfiguration=; securityContactConfiguration=; 
                 pricingConfiguration=}

    id         : /subscriptions/<subscriptionId>/providers/Microsoft.Security/policies/policy2
    name       : default
    type       : Microsoft.Security/policies
    properties : @{policyLevel=Subscription; name=policy2; unique=On; logCollection=On; recommendations=; logsConfiguration=; omsWorkspaceConfiguration=; securityContactConfiguration=; 
                 pricingConfiguration=}

   Fetches details for all policies.
.EXAMPLE
   (Get-ASCPolicy -PolicyName default).properties.recommendations

    patch                   : On
    baseline                : On
    antimalware             : On
    diskEncryption          : On
    acls                    : On
    nsgs                    : On
    waf                     : On
    sqlAuditing             : On
    sqlTde                  : On
    ngfw                    : On
    vulnerabilityAssessment : On
    storageEncryption       : On
    jitNetworkAccess        : On

   The above example fetches default policy and displays the current recommendations settings.
#>
function Get-ASCPolicy
{
    [CmdletBinding()]
    Param
    (
        # Fetches a specific policy by name.
        [Parameter(Mandatory=$false,
                   ValueFromPipelineByPropertyName=$false,
                   Position=0,
                   ParameterSetName='Fetch')]
        [String]$PolicyName,

        # Security API version. By default this uses the $asc_version variable which this module pre-sets. Only specify this if necessary.
        [Parameter(Mandatory=$false)]
        [string]$Version = $asc_version
    )

    Begin
    {
        Set-ASCVars        
        $asc_endpoint = 'policies' #Set endpoint.
        $asc_APIVersion = "?api-version=$version" #Build version syntax.
        Set-ASCAuth
    }
    Process
    {
        
        If ($PSCmdlet.ParameterSetName -ne 'Fetch')
            {
                $asc_uri = "https://$asc_url/subscriptions/$asc_subscriptionId/providers/microsoft.Security/$asc_endpoint$asc_APIVersion"
                Try
                    {
                        $asc_request = Invoke-RestMethod -Uri $asc_uri -Method Get -Headers $asc_requestHeader
                    }
                Catch [System.Net.WebException] 
                    {
                        Write-Error $_
                    }
                Finally 
                    {
                        $asc_request.value
                    }
            }
        
        If ($PolicyName -and !$Baseline)
            {
                $asc_uri = "https://$asc_url/subscriptions/$asc_subscriptionId/providers/microsoft.Security/$asc_endpoint/$PolicyName$asc_APIVersion"
                Try
                    {
                        Write-Verbose "Retrieving data for $PolicyName..."
                        $asc_request = Invoke-RestMethod -Uri $asc_uri -Method Get -Headers $asc_requestHeader
                    }
                Catch 
                    {
                        Write-Error $_
                    }
                Finally
                    {
                        $asc_request
                    }
            }
        If ($PolicyName -and $Baseline) #Placeholder for when baselines get added
            {
                $asc_uri = "https://$asc_url/subscriptions/$asc_subscriptionId/providers/microsoft.Security/$asc_endpoint/$PolicyName/baselineConfigurations$asc_APIVersion"
                Try
                    {
                        Write-Verbose "Retrieving data for $PolicyName..."
                        $asc_request = Invoke-RestMethod -Uri $asc_uri -Method Get -Headers $asc_requestHeader
                    }
                Catch 
                    {
                        Write-Error $_
                    }
                Finally
                    {
                        $asc_request
                    }
            }
    }
    End
    {
    }
}
<#
.Synopsis
   Set-ASCPolicy is used to update the current protection policy for your active subscription. 
.DESCRIPTION
   This cmdlet currently only works for the default policy in your active subscription. To change your active subscription either re-run Get-ASCCredential and select the desired subscription from the list, or run ($asc_subscriptionId = <your subscription id>) to change the global variable used by this module.
.EXAMPLE
   Set-ASCPolicy -PolicyName default -JSON (Build-ASCJSON -Policy -DataCollection On -SecurityContactEmail hello@world.com, bin@bash.com)

   The above example uses the Set-ASCPolicy cmdlet against the default policy for the active subscriptionId and passes in the JSON configuration by running Build-ASCJSON within parentheses. 

   The Build-ASCJSON parameters specified will turn on data collection and replace the existing security contact email addresses with two new addresses.

   The command should return a StatusCode: 200 (OK)

   You can verify your updated configuration by running Get-ASCPolicy.
#>
function Set-ASCPolicy
{
    [CmdletBinding()]
    Param
    (
        # Fetches a specific policy by name.
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$false,
                   Position=0)]
        [String]$PolicyName,

        # Fetches a specific policy by name.
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$false)]
        [string]$JSON,        

        # Security API version. By default this uses the $asc_version variable which this module pre-sets. Only specify this if necessary.
        [Parameter(Mandatory=$false)]
        [string]$Version = $asc_version
    )

    Begin
    {
        Set-ASCVars
        Set-ASCAuth
        $asc_endpoint = 'policies' #Set endpoint.
        $asc_APIVersion = "?api-version=$version" #Build version syntax.
    }
    Process
    {
        
        $asc_uri = "https://$asc_url/subscriptions/$asc_subscriptionId/providers/microsoft.Security/$asc_endpoint/$PolicyName$asc_APIVersion"

        $result = Invoke-WebRequest -Uri $asc_uri -Method Put -Headers $asc_requestHeader -Body $JSON -UseBasicParsing -ContentType "application/json"

        $result.StatusDescription

    }
    End
    {
    }
}
#endregion
#region ASC Status
<#
.Synopsis
   Get-ASCStatus retrieves the data collection status of all resources currently being protected in your active subscription.
.DESCRIPTION
   This cmdlet will display the monitoring health and status of your azure resources for the active subscription. This data is based on data collection being enabled for your resources which can be set in your policy.
.EXAMPLE
    (Get-ASCStatus | ?{$_.id -match 'Kali-01$'}).properties


    vmAgent                              : On
    dataCollector                        : Off
    dataCollectorInstallationStatus      : FailureDueToVmStopped
    dataCollectorPolicy                  : On
    antimalwareScannerData               : @{antimalwareInstallationSecurityState=None; antimalwareSupportLogCollectionSecurityState=None; antimalwareHealthIssuesSecurityState=None; antimalwareComponentList=System.Object[]; 
                                           dataType=Antimalware; isScannerDataValid=False; policy=On; dataExists=False; securityState=None; lastReportTime=0001-01-01T00:00:00}
    baselineScannerData                  : @{failedRulesSecurityState=None; dataType=Baseline; isScannerDataValid=False; policy=On; dataExists=False; securityState=None; lastReportTime=0001-01-01T00:00:00}
    patchScannerData                     : @{rebootPendingSecurityState=None; missingPatchesSecurityState=None; dataType=Patch; isScannerDataValid=False; policy=On; dataExists=False; securityState=None; 
                                           lastReportTime=0001-01-01T00:00:00}
    vmInstallationsSecurityState         : Medium
    encryptionDataState                  : @{securityState=None; isSupported=False; isOsDiskEncrypted=False; isDataDiskEncrypted=False}
    vulnerabilityAssessmentScannerStatus : @{isSupported=False; provider=Unknown; dataType=VulnerabilityAssessment; isScannerDataValid=False; policy=On; dataExists=False; securityState=None; lastReportTime=0001-01-01T00:00:00}
    name                                 : VirtualMachineHealthStateProperties
    type                                 : VirtualMachine
    securityState                        : Medium

    The above example retrieves the data collection status for the Kali-O1 VM and displays the properties.
#>
function Get-ASCStatus
{
    [CmdletBinding()]
    Param
    (
        # Security API version. By default this uses the $asc_version variable which this module pre-sets. Only specify this if necessary.
        [Parameter(Mandatory=$false)]
        [string]$Version = $asc_version
    )

    Begin
    {
        Set-ASCVars
        Set-ASCAuth
        $asc_endpoint = 'securityStatuses' #Set endpoint.
        $asc_APIVersion = "?api-version=$version" #Build version syntax.
    }
    Process
    {
        $asc_uri = "https://$asc_url/subscriptions/$asc_subscriptionId/providers/microsoft.Security/$asc_endpoint$asc_APIVersion"
        Try
            {
                $asc_request = Invoke-RestMethod -Uri $asc_uri -Method Get -Headers $asc_requestHeader
            }
        Catch
            {
                Write-Error $_
            }
        Finally 
            {
                $asc_request.value
            }
    }
    End
    {
    }
}
#endregion
#region ASC Tasks
<#
.Synopsis
   Get-ASCTask displays the current tasks in Azure Security Center.
.DESCRIPTION
   This cmdlet displays the available tasks for your resources in the active subscription. These tasks are based on your set recommendations set in your policy. 
.EXAMPLE
    (Get-ASCTask).properties.securitytaskparameters | select storageaccountname, name

    storageAccountName       name                                                 
    ------------------       ----                                                 
    defaultnetworkingdiag494 Enable encryption for Azure Storage Account          
                             VirtualMachinesNsgShouldRestrictTrafficTaskParameters
                             VirtualMachinesNsgShouldRestrictTrafficTaskParameters
                             ProvisionNgfw                                        
    w10x6401disks523         Enable encryption for Azure Storage Account          
                             NetworkSecurityGroupMissingOnSubnet                  
                             NetworkSecurityGroupMissingOnSubnet                  
    122193westus2            Enable encryption for Azure Storage Account          
                             EncryptionOnVm                                       
                             ProvisionNgfw                                        
                             UpgradePricingTierTaskParameters                     
    defaultnetworking698     Enable encryption for Azure Storage Account          


    The above example retrives the available tasks displays the relevant storage account and task name only.
#>
function Get-ASCTask
{
    [CmdletBinding()]
    Param
    (
        # Security API version. By default this uses the $asc_version variable which this module pre-sets. Only specify this if necessary.
        [Parameter(Mandatory=$false)]
        [string]$Version = $asc_version
    )

    Begin
    {
        Set-ASCVars
        Set-ASCAuth
        $asc_endpoint = 'tasks' #Set endpoint.
        $asc_APIVersion = "?api-version=$version" #Build version syntax.
    }
    Process
    {
        $asc_uri = "https://$asc_url/subscriptions/$asc_subscriptionId/providers/microsoft.Security/$asc_endpoint$asc_APIVersion"
        Try
            {
                $asc_request = Invoke-RestMethod -Uri $asc_uri -Method Get -Headers $asc_requestHeader
            }
        Catch
            {
                Write-Error $_
            }
        Finally 
            {
                $asc_request.value
            }
    }
    End
    {
    }
}
<#
.Synopsis
   Set-ASCTask updates the status of a task
.DESCRIPTION
   This cmdlet can be used to update task status to either dismiss or activate. 
.EXAMPLE
   Set-ASCTask -TaskID 09eb1b85-1b5b-c4b6-5ad3-b3c383b1a83d -Dismiss

   (Get-ASCTask).properties | select -first 1

    state    
    -----    
    Dismissed

   The first command marks the set task as dismissed. The second command checks the status of the updated task and displays the state.

#>
function Set-ASCTask
{
    [CmdletBinding()]
    Param
    (
        # Task ID
        [Parameter(Mandatory=$false,
                   ValueFromPipeline=$true,
                   ValueFromPipelineByPropertyName=$true,
                   Position=0)]
        [alias("name")]
        [string[]]$TaskID,

        # Dismiss Flag
        [Parameter(Mandatory=$false,
                   ValueFromPipelineByPropertyName=$false,
                   ParameterSetName='Dismiss')]
        [switch]$Dismiss,

        # Activate Flag
        [Parameter(Mandatory=$false,
                   ValueFromPipelineByPropertyName=$false,
                   ParameterSetName='Activate')]
        [switch]$Activate,

        # Security API version. By default this uses the $asc_version variable which this module pre-sets. Only specify this if necessary.
        [Parameter(Mandatory=$false)]
        [string]$Version = $asc_version
    )

    Begin
    {
        Set-ASCVars
        Set-ASCAuth
        $asc_endpoint = 'tasks' #Set endpoint.
        $asc_APIVersion = "?api-version=$version" #Build version syntax.
    }
    Process
    {
        If ($PSCmdlet.ParameterSetName -eq 'Dismiss') #Run this block if Dismiss flag is used
            {
                $asc_uri = "https://$asc_url/subscriptions/$asc_subscriptionId/providers/microsoft.Security/locations/centralus/$asc_endpoint/$TaskID/dismiss$asc_APIVersion"
                Try
                    {
                        $asc_request = Invoke-RestMethod -Uri $asc_uri -Method Post -Headers $asc_requestHeader
                    }
                Catch
                    {
                        Write-Error $_
                    }
                Finally 
                    {
                        $asc_request
                    }
            }
        
        If ($PSCmdlet.ParameterSetName -eq 'Activate') #Run this block if Activate flag is used
            {
                $asc_uri = "https://$asc_url/subscriptions/$asc_subscriptionId/providers/microsoft.Security/locations/centralus/$asc_endpoint/$TaskID/activate$asc_APIVersion"
                Try
                    {
                        $asc_request = Invoke-RestMethod -Uri $asc_uri -Method Post -Headers $asc_requestHeader
                    }
                Catch 
                    {
                        Write-Error $_
                    }
                Finally
                    {
                        $asc_request
                    }
            }
    }
    End
    {
    }
}
#endregion
#region ASC Alerts
<#
.Synopsis
   Get-ASCAlert
.DESCRIPTION
   This cmdlet receives a collection of alerts. Note, alerts are only avaible in Standart-tier subscriptions.
.EXAMPLE
    Get-ASCAlert | select -First 20 @{N='Alert';E={$_.properties.alertdisplayname}}

    Alert                                                                                              
    -----                                                                                              
    Potential SQL Injection                                                                            
    Deep Security Agent detected a malware                                                             
    Possible outgoing spam activity detected                                                           
    Modified system binary discovered in dump file 5bd767e4-2d08-4714-b744-aaed04b57107__391365252.hdmp
    Security incident detected                                                                         
    Network communication with a malicious machine detected                                            
    Multiple Domain Accounts Queried                                                                   
    Suspicious SVCHOST process executed                                                                
    Successful RDP brute force attack                                                                  
    Failed RDP Brute Force Attack                                                                      

    The above command retrieves the last 20 alerts and shows them in a table, renaming the alertdisplayname property to 'Alert'.                                                           
#>

function Get-ASCAlert
{
    [CmdletBinding()]
    Param
    (   
        # Specify Alert ID to fetch a specific ASC Alert. If this is not set, this cmdlet will retrieve a collection of all alerts.
        [Parameter(Mandatory=$false,
                   ValueFromPipelineByPropertyName=$true,
                   Position=0,
                   ParameterSetName='Fetch')]
        [alias("id")]
        [string[]]$AlertID,

        # Security API version. By default this uses the $asc_version variable which this module pre-sets. Only specify this if necessary.
        [Parameter(Mandatory=$false)]
        [string]$Version = $asc_version
    )

    Begin
    {
        Set-ASCVars
        Set-ASCAuth
        $asc_endpoint = 'alerts' #Set endpoint.
        $asc_APIVersion = "?api-version=$version" #Build version syntax.
    }
    Process
    {
        Try
            {
                if ($PSCmdlet.ParameterSetName -eq 'Fetch')
                    {
                        foreach ($i in $AlertID)
                            {
                                if ($i -match '^/') {$i = ($i -split '/alerts/' | ?{$_ -notmatch '^/'})}
                                $asc_uri = "https://$asc_url/subscriptions/$asc_subscriptionId/providers/microsoft.Security/locations/centralus/$asc_endpoint/$i$asc_APIVersion"
                                $asc_request = Invoke-RestMethod -Uri $asc_uri -Method Get -Headers $asc_requestHeader
                                $asc_request
                            }
                    }
                else 
                    {
                                $asc_uri = "https://$asc_url/subscriptions/$asc_subscriptionId/providers/microsoft.Security/locations/centralus/$asc_endpoint$asc_APIVersion"
                                $asc_request = Invoke-RestMethod -Uri $asc_uri -Method Get -Headers $asc_requestHeader
                                $asc_request.value
                    }
            }
        Catch
            {
                Write-Error $_
            }
        Finally 
            {
            }
    }
    End
    {
    }
}
<#
.Synopsis
   Set-ASCAlert changes the status of an alert.
.DESCRIPTION
   Changes the status of alerts.
.EXAMPLE
   <example>
#>
function Set-ASCAlert
{
    [CmdletBinding()]
    Param
    (
        # Alert ID
        [Parameter(Mandatory=$false,
                   ValueFromPipeline=$true,
                   ValueFromPipelineByPropertyName=$true,
                   Position=0)]
        [alias('id')]
        [string[]]$AlertID,

        # Dismiss Flag
        [Parameter(Mandatory=$false,
                   ValueFromPipelineByPropertyName=$false,
                   ParameterSetName='Dismiss')]
        [switch]$Dismiss,

        # Activate Flag
        [Parameter(Mandatory=$false,
                   ValueFromPipelineByPropertyName=$false,
                   ParameterSetName='Activate')]
        [switch]$Activate,

        # Security API version. By default this uses the $asc_version variable which this module pre-sets. Only specify this if necessary.
        [Parameter(Mandatory=$false)]
        [string]$Version = $asc_version
    )

    Begin
    {
        Set-ASCVars
        Set-ASCAuth
        $asc_endpoint = 'alerts' #Set endpoint.
        $asc_APIVersion = "?api-version=$version" #Build version syntax.
    }
    Process
    {
        If ($Dismiss -and !$Activate) #Run this block if Dismiss flag is used
            {
                Try
                    {
                        foreach ($i in $AlertID) 
                            {
                                if ($i -match '^/') { $i = ($i -split '/alerts/' | ?{$_ -notmatch '^/'})}
                                Write-Warning "Dismissing alert $i"
                                $asc_uri = "https://$asc_url/subscriptions/$asc_subscriptionId/providers/microsoft.Security/locations/centralus/$asc_endpoint/$i/dismiss$asc_APIVersion"
                                $asc_request = Invoke-RestMethod -Uri $asc_uri -Method Post -Headers $asc_requestHeader | Out-Null
                            }
                    }
                Catch
                    {
                        Write-Error $_
                    }
                Finally 
                    {
                    }
            }
        
        If ($Activate -and !$Dismiss) #Run this block if Activate flag is used
            {
                Try
                    {
                        foreach ($i in $AlertID) 
                            { 
                                if ($i -match '^/') { $i = ($i -split '/alerts/' | ?{$_ -notmatch '^/'})}
                                Write-Warning "Activating alert $i"
                                $asc_uri = "https://$asc_url/subscriptions/$asc_subscriptionId/providers/microsoft.Security/locations/centralus/$asc_endpoint/$i/activate$asc_APIVersion"
                                $asc_request = Invoke-RestMethod -Uri $asc_uri -Method Post -Headers $asc_requestHeader | Out-Null
                            }
                    }
                Catch 
                    {
                        Write-Error $_
                    }
                Finally
                    {
                        $asc_request
                    }
            }
        If ($Activate -and $Dismiss)
            { 
                Write-Warning "You may not specify -Activate and -Dismiss at the same time."
                break
            }
    }
    End
    {
    }
}
#endregion
#region ASC Data Collection
<#
.Synopsis
   Get-ASCDataCollection
.DESCRIPTION
   Retrieves data collection information around the specified resource.
.EXAMPLE
    PS C:\> Get-ASCDataCollection -ComputeType Compute -ResourceGroup CXP-MIKE -VM "2012R2-DC1" | fl -Force


    id         : /subscriptions/6b1ceacd-5921-4780-8f96-2078ad96fd96/resourceGroups/CXP-MIKE/providers/Microsoft.Compute/virtualMachines/2012R2-DC1//providers/Micros
                 oft.Security/securityStatuses/Patch
    name       : Patch
    type       : Microsoft.Security/securityStatuses
    properties : @{missingPatches=System.Object[]; name=PatchSecurityDataProperties; type=Patch}

    id         : /subscriptions/6b1ceacd-5921-4780-8f96-2078ad96fd96/resourceGroups/CXP-MIKE/providers/Microsoft.Compute/virtualMachines/2012R2-DC1//providers/Micros
                 oft.Security/securityStatuses/Baseline
    name       : Baseline
    type       : Microsoft.Security/securityStatuses
    properties : @{failedBaselineRules=System.Object[]; name=BaselineSecurityDataProperties; type=Baseline}

    id         : /subscriptions/6b1ceacd-5921-4780-8f96-2078ad96fd96/resourceGroups/CXP-MIKE/providers/Microsoft.Compute/virtualMachines/2012R2-DC1//providers/Micros
                 oft.Security/securityStatuses/Antimalware
    name       : Antimalware
    type       : Microsoft.Security/securityStatuses
    properties : @{antimalwareScenarios=System.Object[]; name=AntimalwareSecurityDataProperties; type=Antimalware}


    The above example retrieves data collection information for the specified resource.

#>
function Get-ASCDataCollection
{
    [CmdletBinding()]
    Param
    (
        # Specify compute type. 'Compute' or 'Classic Compute'
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$false)]
        [ValidateSet('Compute','Classic Compute')]
        [string]$ComputeType,

        # Specify resource group.
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$false)]
        [string]$ResourceGroup,

        # Specify VM name.
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$false)]
        [string]$VM,

        # Security API version. By default this uses the $asc_version variable which this module pre-sets. Only specify this if necessary.
        [Parameter(Mandatory=$false)]
        [string]$Version = $asc_version
    )

    Begin
    {
        Set-ASCVars
        Set-ASCAuth
        $asc_endpoint = 'dataCollectionResults' #Set endpoint.
        $asc_APIVersion = "?api-version=$version" #Build version syntax.
        $asc_resourceGroup = $ResourceGroup
        $asc_compute = $ComputeType
        $asc_vm = $VM
    }
    Process
    {
        $asc_uri = "https://$asc_url/subscriptions/$asc_subscriptionId/resourceGroups/$asc_resourceGroup/providers/microsoft.$asc_compute/virtualMachines/$asc_vm/providers/microsoft.Security/$asc_endpoint$asc_APIVersion"
        Try
            {
                Write-Verbose "Retrieving data for $asc_vm..."
                $asc_request = Invoke-RestMethod -Uri $asc_uri -Method Get -Headers $asc_requestHeader
            }
        Catch
            {
                Write-Error $_
            }
        Finally 
            {
                $asc_request
            }
    }
    End
    {
    }
}
#endregion
#region ASC Location
#region Get-ASCLocation
<#
.Synopsis
   Get-ASCLocation
.DESCRIPTION
   Retrieves data center location information for Azure Security Center data.
.EXAMPLE
    PS C:\> Get-ASCLocation | fl -Force


    id         : /subscriptions/6b1ceacd-5731-4780-8f96-2078dd96fd96/providers/Microsoft.Security/locations/centralus
    name       : centralus
    type       : Microsoft.Security/locations
    properties : @{homeRegionName=centralus}


    The above example retrieves datacenter region information for the ASC service.
#>
function Get-ASCLocation
{
    [CmdletBinding()]
    Param
    (
        # Security API version. By default this uses the $asc_version variable which this module pre-sets. Only specify this if necessary.
        [Parameter(Mandatory=$false)]
        [string]$Version = $asc_version
    )

    Begin
    {
        Set-ASCVars
        Set-ASCAuth
        $asc_endpoint = 'locations' #Set endpoint.
        $asc_APIVersion = "?api-version=$version" #Build version syntax.
    }
    Process
    {
            $asc_uri = "https://$asc_url/subscriptions/$asc_subscriptionId/providers/microsoft.Security/$asc_endpoint$asc_APIVersion"
            Try
                {
                    $asc_request = Invoke-RestMethod -Uri $asc_uri -Method Get -Headers $asc_requestHeader
                }
            Catch
                {
                    Write-Error $_
                }
            Finally 
                {
                    $asc_request.value
                }
    }
    End
    {
    }
}
#endregion
#endregion
#region ASC Security Solutions
#region Get-ASCSecuritySolutionReferenceData
<#
.Synopsis
   Get-ASCSecuritySolutionReferenceData
.DESCRIPTION
   Retrieves list of available partner solutions and their corrosponding information.
.EXAMPLE
    PS C:\> Get-ASCSecuritySolutionReferenceData | ?{$_.name -match 'barracuda'} | fl -Force


    id         : /subscriptions/6b1ceacd-5731-4780-8f96-2078dd96fd96/providers/Microsoft.Security/securitySolutionsReferenceData/barracudanetworks.wafbyol-ARM.FullyI
                 ntegrated
    name       : barracudanetworks.wafbyol-ARM.FullyIntegrated
    type       : Microsoft.Security/securitySolutionsReferenceData
    properties : @{alertVendorName=BarracudaWAF; securityFamily=Waf; packageInfoUrl=www.azure.com; productName=Web Application Firewall; 
                 provisionType=FullyIntegrated; publisher=barracudanetworks; publisherDisplayName=Barracuda Networks, Inc.; template=barracudanetworks/wafbyol-ARM}

    id         : /subscriptions/6b1ceacd-5731-4780-8f96-2078dd96fd96/providers/Microsoft.Security/securitySolutionsReferenceData/barracudanetworks.wafbyol-ARM
    name       : barracudanetworks.wafbyol-ARM
    type       : Microsoft.Security/securitySolutionsReferenceData
    properties : @{alertVendorName=BarracudaWAF; securityFamily=Waf; packageInfoUrl=www.azure.com; productName=Web Application Firewall; 
                 provisionType=SemiIntegrated; publisher=barracudanetworks; publisherDisplayName=Barracuda Networks, Inc.; template=barracudanetworks/wafbyol-ARM}

    id         : /subscriptions/6b1ceacd-5731-4780-8f96-2078dd96fd96/providers/Microsoft.Security/securitySolutionsReferenceData/barracudanetworks.barracuda-ng-firew
                 allbyol-ARM
    name       : barracudanetworks.barracuda-ng-firewallbyol-ARM
    type       : Microsoft.Security/securitySolutionsReferenceData
    properties : @{alertVendorName=BarracudaNgfw; securityFamily=Ngfw; packageInfoUrl=www.azure.com; productName=Next Generation Firewall; 
                 provisionType=SemiIntegrated; publisher=barracudanetworks; publisherDisplayName=Barracuda Networks, Inc.; 
                 template=barracudanetworks/barracuda-ng-firewallbyol-ARM}


    The above command retrieves available Barracuda partner solutions and displays corrosponding data.
#>
function Get-ASCSecuritySolutionReferenceData
{
    [CmdletBinding()]
    Param
    (
        # Security API version. By default this uses the $asc_version variable which this module pre-sets. Only specify this if necessary.
        [Parameter(Mandatory=$false)]
        [string]$Version = $asc_version
    )

    Begin
    {
        Set-ASCVars
        Set-ASCAuth
        $asc_endpoint = 'securitySolutionsReferenceData' #Set endpoint.
        $asc_APIVersion = "?api-version=$version" #Build version syntax.
    }
    Process
    {
        $asc_uri = "https://$asc_url/subscriptions/$asc_subscriptionId/providers/microsoft.Security/$asc_endpoint$asc_APIVersion"
        Try
            {
                $asc_request = Invoke-RestMethod -Uri $asc_uri -Method Get -Headers $asc_requestHeader
            }
        Catch
            {
                Write-Error $_
            }
        Finally 
            {
                $asc_request.value
            }
    }
    End
    {
    }
}
#endregion
#region Get-ASCSecuritySolution
<#
.Synopsis
   Get-ASCSecuritySolution retrieves the list of deployed partner solutions.
.DESCRIPTION
   Retrieves currently deployed partner solutions and corrosponding data.
.EXAMPLE
    PS C:\> Get-ASCSecuritySolution | select -ExpandProperty properties


    securityFamily           : SaasWaf
    integrationLevel         : SemiIntegrated
    protectionStatus         : Good
    template                 : Microsoft.ApplicationGateway-ARM
    protectedResourcesStates : {}
    protectedResourcesTypes  : {}
    managementUrl            : https://portal.azure.com#resource/subscriptions/6b1cebbd-5731-4780-8f96-2078da96fd96/resourceGroups/ASC-Playbook/providers/Microsoft.N
                               etwork/applicationGateways/ASC-Playbook-WAG/overview
    creationDate             : 2017-04-25T05:29:04.2645167Z
    provisioningState        : Succeeded
    clusterId                : 3BFDEEB35202166EC0A77A5C4B1D125C0A28CD51


    The above command displays currently deployed partner solutions and their corrosponding data.
#>
function Get-ASCSecuritySolution
{
    [CmdletBinding()]
    Param
    (
        # Security API version. By default this uses the $asc_version variable which this module pre-sets. Only specify this if necessary.
        [Parameter(Mandatory=$false)]
        [string]$Version = $asc_version
    )

    Begin
    {
        Set-ASCVars
        Set-ASCAuth
        $asc_endpoint = 'securitySolutions' #Set endpoint.
        $asc_APIVersion = "?api-version=$version" #Build version syntax.
    }
    Process
    {
        $asc_uri = "https://$asc_url/subscriptions/$asc_subscriptionId/providers/microsoft.Security/$asc_endpoint$asc_APIVersion"
        Try
            {
                $asc_request = Invoke-RestMethod -Uri $asc_uri -Method Get -Headers $asc_requestHeader
            }
        Catch
            {
                Write-Error $_
            }
        Finally 
            {
                $asc_request.value
            }
    }
    End
    {
    }
}
#endregion
#region Set-ASCProtectedResource
<#
.Synopsis
   
.DESCRIPTION

.EXAMPLE

#>
function Set-ASCProtectedResource
{
    [CmdletBinding()]
    Param
    (
        # The name of the security solution
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$false,
                   Position=0)]
        [String]$SolutionName,

        # The name of the resource group of the security solution
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$false,
                   Position=0)]
        [String]$ResourceGroupName,

        # Fetches a specific policy by name.
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$false)]
        [string]$JSON,        

        # Security API version. By default this uses the $asc_version variable which this module pre-sets. Only specify this if necessary.
        [Parameter(Mandatory=$false)]
        [string]$Version = $asc_version
    )

    Begin
    {
        Write-Warning "This cmdlet is currently in development and may not work as expected."
        Set-ASCVars
        Set-ASCAuth
        $asc_endpoint = 'securitySolutions' #Set endpoint.
        $asc_APIVersion = "?api-version=$version" #Build version syntax.
    }
    Process
    {
        
        $asc_uri = "https://$asc_url/subscriptions/$asc_subscriptionId/resourceGroups/$ResourceGroupName/providers/microsoft.Security/$asc_endpoint/$SolutionName/protectedResources$asc_APIVersion"

        $result = Invoke-WebRequest -Uri $asc_uri -Method Put -Headers $asc_requestHeader -Body $JSON -UseBasicParsing -ContentType "application/json"

        $result

    }
    End
    {
    }
}
#endregion
#endregion
#region ASC JIT Network Access
#region Get-ASCJITAccessPolicy
<#
.Synopsis
   Get-ASCJITAccessPolicy retrieves all of your currently set JIT policies in the current subscription.
.DESCRIPTION
   This cmdlet gets a list of all set JIT policies that can be used to invoke JIT on a particular resource using the Invoke-ASCJITAccess cmdlet.
.EXAMPLE
    Get-ASCJITAccessPolicy | select -first 1 | fl -force

    properties : @{vmId=/subscriptions/6b1ccdcd-5731-4780-8556-2078dd96fdcc/resourceGroups/ContosoRG/providers/Microsoft.Compute/virtualMachines/DC1; ports=System.Object[]; 
                 requests=System.Object[]; provisioningState=Succeeded}
    id         : /subscriptions/6b1ccdcd-5731-4780-8556-2078dd96fdcc/resourceGroups/ContosoRGE/providers/Microsoft.Compute/virtualMachines/DC1/providers/Microsoft.Security/jitN
                 etworkAccessPolicies/default
    name       : default
    type       : Microsoft.Security/jitNetworkAccessPolicies

    The above example retrieves the list of JIT policies, selects the first one, and displays the properties as a list.
#>
function Get-ASCJITAccessPolicy
{
    [CmdletBinding()]
    Param
    (
        # Security API version. By default this uses the $asc_version variable which this module pre-sets. Only specify this if necessary.
        [Parameter(Mandatory=$false)]
        [string]$Version = $asc_version
    )

    Begin
    {
        Set-ASCVars
        Set-ASCAuth
        $asc_endpoint = 'jitNetworkAccessPolicies' #Set endpoint.
        $asc_APIVersion = "?api-version=$version" #Build version syntax.
    }
    Process
    {
        Write-Warning "This cmdlet leverages a feature that is in private preview and will not work if your tenant is not configured for JIT Access."
        $asc_uri = "https://$asc_url/subscriptions/$asc_subscriptionId/providers/microsoft.Security/$asc_endpoint$asc_APIVersion"
        Try
            {
                $asc_request = Invoke-RestMethod -Uri $asc_uri -Method Get -Headers $asc_requestHeader
            }
        Catch
            {
                Write-Error $_
            }
        Finally 
            {
                $asc_request.value
            }
    }
    End
    {
    }
}
#region Set-ASCJITAccessPolicy
<#
.Synopsis
   Set-ASCJITAccessPolicy is used to enable or disable JIT on specified VM's.
.DESCRIPTION
   
.EXAMPLE

#>
function Set-ASCJITAccessPolicy
{
    [CmdletBinding()]
    Param
    (
        # The name of the resource group of the security solution
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$false,
                   Position=0)]
        [String]$ResourceGroupName,
       
        # The name of the VM to enable JIT on.
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$false,
                   Position=1)]
        [String]$VM,
        
        # Security API version. By default this uses the $asc_version variable which this module pre-sets. Only specify this if necessary.
        [Parameter(Mandatory=$false)]
        [string]$Version = $asc_version
    )

    Begin
    {
        Set-ASCVars
        Set-ASCAuth
        $asc_endpoint = 'jitNetworkAccessPolicies' #Set endpoint.
        $asc_APIVersion = "?api-version=$version" #Build version syntax.
        
        $asc_location = (Get-AzureRMResourceGroup -Name $ResourceGroupName).location
        $asc_vm_id = (Get-AzureRMVM -ResourceGroupName $ResourceGroupName -Name $VM).Id
        

$JSON = @'
{
    "kind": "Basic",
    "type": "Microsoft.Security/locations/jitNetworkAccessPolicies",
    "name": "default",
    "id": "/subscriptions/e5d1b86c-3051-44d5-8802-aa65d45a279b/resourceGroups/CxP-Mike/providers/Microsoft.Security/locations/westus2/jitNetworkAccessPolicies/default",
    "properties": {
        "virtualMachines": [{
            "id": "/subscriptions/e5d1b86c-3051-44d5-8802-aa65d45a279b/resourceGroups/CxP-Mike/providers/Microsoft.Compute/virtualMachines/2016-Nano1",
            "ports": [{
                "maxRequestAccessDuration": "PT3H",
                "number": 22,
                "allowedSourceAddressPrefix": "*"
            }]
        }]
    }
} 
'@


<#
        $Body = @{}
        $Body += @{
            kind = "Basic"
            properties = @{
                virtualMachines = @(@{
                    id = "$asc_vm_id"
                        ports = @(@{
                            number = 22
                            allowedSourceAddressPrefix = "*"
                            maxRequestAccessDuration = "PT3H"})
                })
            }
            id = "/subscriptions/$asc_subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Security/locations/$asc_location/$asc_endpoint/default"
            name = "default"
            type = "Microsoft.Security/locations/jitNetworkAccessPolicies"}
        
        $JSON = $Body | ConvertTo-Json -Depth 4
        $JSON
#>
    }
    Process
    {
        Write-Warning "This cmdlet leverages a feature that is in private preview and will not work if your tenant is not configured for JIT Access."
        $asc_uri = "https://$asc_url/subscriptions/$asc_subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Security/locations/$asc_location/$asc_endpoint/default$asc_APIVersion"
        Try
            {
                Invoke-RestMethod -Uri $asc_uri -Method Put -Headers $asc_requestHeader -Body $JSON
            }
        Catch
            {
                Write-Error $_
            }
        Finally 
            {
                
            }
    }
    End
    {
    }
}
<#
.Synopsis
    Invoke-ASCJITAccess is used to invoke JIT access to an Azure VM.
.DESCRIPTION

.EXAMPLE

#>
function Invoke-ASCJITAccess
{
    [CmdletBinding()]
    Param
    (
        # The specified JIT Policy.
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$false,
                   Position=0)]
        [String]$ResourceGroupName,

        # The JSON configuration.
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$false)]
        [string]$VM,     

        # The JSON configuration.
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$false)]
        [string[]]$Port,   
        
        # Security API version. By default this uses the $asc_version variable which this module pre-sets. Only specify this if necessary.
        [Parameter(Mandatory=$false)]
        [string]$Version = $asc_version
    )

    Begin
    {
        Set-ASCVars
        Set-ASCAuth
        $asc_endpoint = 'jitNetworkAccessPolicies' #Set endpoint.
        $asc_APIVersion = "?api-version=$version" #Build version syntax.

        $location = (Get-AzuerRMVM -resourcegroupname $ResourceGroupName -Name $VM).location

        $Body = @{
            virtualMachines = @{
                id = "/subscriptions/$asc_subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Compute/virtualMachines/$VM"
                ports = @{
                    value = $Port
                    allowedSourceAddressPrefix = ""
                    endTimeUtc = ([DateTime]::UtcNow.AddHours(3).ToString("o"))
                }
            }
        }

    }
    Process
    {
        Write-Warning "This cmdlet leverages a feature that is in private preview and will not work if your tenant is not configured for JIT Access."
        Write-Warning "This cmdlet may break in the near future!"
        $asc_uri = "https://$asc_url/subscriptions/$asc_subscriptionId/resourceGroups/$ResourceGroupName/providers/microsoft.Security/locations/$location/$asc_endpoint/default/initiate$asc_APIVersion"
        Try
            {
                $asc_request = Invoke-RestMethod -Uri $asc_uri -Method Post -Body $Body -Headers $asc_requestHeader
            }
        Catch
            {
                Write-Error $_
            }
        Finally
            {
                $asc_request.value
            }
    }
    End
    {
    }
}
#endregion

#endregion
#endregion


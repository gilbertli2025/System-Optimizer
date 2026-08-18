@{
    'Rules' = @{
        'PSUseApprovedVerbs' = @{ 'Enable' = $true }
        'PSAvoidUsingCmdletAliases' = @{
            'Enable' = $true
            'ExcludedCmdlets' = @('Write-Host', '%')
        }
        'PSAvoidUsingEmptyCatchBlock' = @{
            'Enable' = $true
            'Severity' = 'Warning'
        }
        'PSAvoidUsingInvoke-Expression' = @{ 'Enable' = $true }
        'PSAvoidTrailingWhitespace' = @{ 'Enable' = $true }
        'PSMissingModuleManifestField' = @{ 'Enable' = $false }
        'PSUseShouldProcessForStateChangingFunctions' = @{ 'Enable' = $false }
    }
}

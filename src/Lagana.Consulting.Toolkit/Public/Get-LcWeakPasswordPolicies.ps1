function Get-LcWeakPasswordPolicies {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $DomainContext,

        [int]$MinPasswordLengthBaseline = 14,

        [int]$MaxPasswordAgeDaysBaseline = 60
    )

    if (-not $DomainContext) {
        throw "DomainContext cannot be null."
    }

    $domain = [string]$DomainContext.DomainFqdn

    $results = @()

    # Check default domain policy
    $defaultPolicy = Get-LcAdDefaultPasswordPolicy -DomainContext $DomainContext
    if ($defaultPolicy) {
        $maxPwdAgeDays = if ($defaultPolicy.MaxPasswordAgeDays -ne $null) { [double]$defaultPolicy.MaxPasswordAgeDays } else { 0 }

        $weaknesses = @()
        if ($defaultPolicy.MinPasswordLength -lt $MinPasswordLengthBaseline) {
            $weaknesses += "MinLength=$($defaultPolicy.MinPasswordLength) (baseline=$MinPasswordLengthBaseline)"
        }
        if ($maxPwdAgeDays -gt $MaxPasswordAgeDaysBaseline -or $maxPwdAgeDays -eq 0) {
            $weaknesses += "MaxAge=$([int]$maxPwdAgeDays)d (baseline=$MaxPasswordAgeDaysBaseline)"
        }
        if ($defaultPolicy.PasswordHistoryCount -lt 24) {
            $weaknesses += "History=$($defaultPolicy.PasswordHistoryCount) (baseline=24)"
        }
        if ($defaultPolicy.ReversibleEncryptionEnabled -eq $true) {
            $weaknesses += "ReversibleEncryption=True"
        }

        if ($weaknesses.Count -gt 0) {
            $results += [pscustomobject]@{
                DomainFqdn    = $domain
                PolicyType    = 'DefaultDomain'
                PolicyName    = 'Default Domain Policy'
                Weaknesses    = ($weaknesses -join ';')
                WeaknessCount = $weaknesses.Count
                RiskLevel     = if ($weaknesses.Count -ge 3) { 'High' } elseif ($weaknesses.Count -ge 2) { 'Medium' } else { 'Low' }
            }
        }
    }

    # Check FGPPs
    $fgpps = Get-LcAdFineGrainedPasswordPolicies -DomainContext $DomainContext
    foreach ($fgpp in $fgpps) {
        $maxPwdAgeDays = if ($fgpp.MaxPasswordAgeDays -ne $null) { [double]$fgpp.MaxPasswordAgeDays } else { 0 }

        $weaknesses = @()
        if ($fgpp.MinPasswordLength -lt $MinPasswordLengthBaseline) {
            $weaknesses += "MinLength=$($fgpp.MinPasswordLength) (baseline=$MinPasswordLengthBaseline)"
        }
        if ($maxPwdAgeDays -gt $MaxPasswordAgeDaysBaseline -or $maxPwdAgeDays -eq 0) {
            $weaknesses += "MaxAge=$([int]$maxPwdAgeDays)d (baseline=$MaxPasswordAgeDaysBaseline)"
        }
        if ($fgpp.PasswordHistoryCount -lt 24) {
            $weaknesses += "History=$($fgpp.PasswordHistoryCount) (baseline=24)"
        }
        if ($fgpp.ReversibleEncryptionEnabled -eq $true) {
            $weaknesses += "ReversibleEncryption=True"
        }

        if ($weaknesses.Count -gt 0) {
            $results += [pscustomobject]@{
                DomainFqdn    = $domain
                PolicyType    = 'FGPP'
                PolicyName    = [string]$fgpp.Name
                Weaknesses    = ($weaknesses -join ';')
                WeaknessCount = $weaknesses.Count
                RiskLevel     = if ($weaknesses.Count -ge 3) { 'High' } elseif ($weaknesses.Count -ge 2) { 'Medium' } else { 'Low' }
            }
        }
    }

    return $results | Sort-Object -Property WeaknessCount -Descending
}

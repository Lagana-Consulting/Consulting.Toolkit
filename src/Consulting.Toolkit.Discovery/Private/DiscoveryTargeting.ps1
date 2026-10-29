function Get-AdDiscoveryDomainDn {
    param([Parameter(Mandatory)][string]$DistinguishedName)
    # Match the final DC components. Escaped commas in an object's name must
    # not be interpreted as the start of its domain naming context.
    $match = [regex]::Match($DistinguishedName, '(?i)(?:^|(?<!\\)(?:\\\\)*,)(?<domain>DC=(?:\\.|[^,])+(?:,DC=(?:\\.|[^,])+)*)$')
    if (-not $match.Success) { throw "Cannot determine the domain naming context from '$DistinguishedName'." }
    return $match.Groups['domain'].Value
}

function Assert-AdDiscoveryDomainRows {
    param([AllowEmptyCollection()][object[]]$Rows, [string]$ExpectedDomainDn)
    if ([string]::IsNullOrWhiteSpace($ExpectedDomainDn)) { return }
    foreach ($row in $Rows) {
        if (-not $row.PSObject.Properties['DistinguishedName'] -or [string]::IsNullOrWhiteSpace([string]$row.DistinguishedName)) {
            throw "The query did not return DistinguishedName; target domain '$ExpectedDomainDn' cannot be verified."
        }
        $actualDomainDn = Get-AdDiscoveryDomainDn -DistinguishedName $row.DistinguishedName
        if (-not [string]::Equals($actualDomainDn, $ExpectedDomainDn, [StringComparison]::OrdinalIgnoreCase)) {
            $exception = New-Object System.InvalidOperationException("Query returned '$($row.DistinguishedName)' from '$actualDomainDn'; expected '$ExpectedDomainDn'. No rows from this query will be exported.")
            $exception.Data['DiscoveryTargetMismatch'] = $true
            throw $exception
        }
    }
}

function Test-AdDiscoveryIdentityNotFound {
    param([System.Management.Automation.ErrorRecord]$ErrorRecord)
    $exception = $ErrorRecord.Exception
    while ($exception) {
        if ($exception.GetType().Name -eq 'ADIdentityNotFoundException') { return $true }
        $exception = $exception.InnerException
    }
    # Compatibility-session proxies may deserialize the exception type, while
    # retaining the original AD cmdlet's fully qualified error identifier.
    return $ErrorRecord.FullyQualifiedErrorId -match '(^|[.:])ADIdentityNotFoundException(,|$)'
}

function Write-AdDiscoveryCollectionIssue {
    param([string]$Message, [System.Management.Automation.ErrorRecord]$ErrorRecord, $Details)
    if (-not $Message -and $ErrorRecord) { $Message = $ErrorRecord.Exception.Message }
    Write-AdDiscoveryEvent -Kind Collector -Status PARTIAL -Message $Message -ErrorRecord $ErrorRecord -Details $Details -MarkIncomplete
    Write-Warning $Message -WarningAction Continue
}

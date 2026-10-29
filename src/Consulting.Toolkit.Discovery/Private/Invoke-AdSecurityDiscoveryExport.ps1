function Invoke-AdSecurityDiscoveryExport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Forest,
        [Parameter(Mandatory)] [string] $ForestDir,

        [Parameter()] $DomainContext,
        [Parameter()] [string] $DomainDir,

        [Parameter(Mandatory)] [string] $ScopeTag,
        [Parameter()] [string] $LogPath
    )

    Set-StrictMode -Version Latest

    if ($DomainContext -and $ScopeTag -notmatch '^Domain-') {
        throw "Invoke-AdSecurityDiscoveryExport: DomainContext provided but ScopeTag '$ScopeTag' is not Domain-<fqdn>."
    }

    function Write-SecLog([string]$msg) {
        if ($LogPath) { try { Add-Content -LiteralPath $LogPath -Value ("[{0}] {1}" -f (Get-Date), $msg) } catch {} }
    }

    function Try-Export([scriptblock]$Action, [string]$Operation) {
        $context = Get-Variable -Name adDiscoveryLogContext -ValueOnly -ErrorAction SilentlyContinue
        if ($context) { Set-AdDiscoveryOperationStatus -Context $context -Operation $Operation -Status START }
        try {
            & $Action
            if ($context) { Set-AdDiscoveryOperationStatus -Context $context -Operation $Operation -Status OK }
            Write-Host "    [OK] $Operation" -ForegroundColor Green
            Write-SecLog "OK  $Operation"
        } catch {
            if ($context) {
                $status = if ($_.Exception.Data['DiscoveryStatus'] -eq 'SKIP') { 'SKIP' } else { 'FAIL' }
                Set-AdDiscoveryOperationStatus -Context $context -Operation $Operation -Status $status -ErrorRecord $_
            }
            Write-Host "    [WARN] $Operation : $($_.Exception.Message)" -ForegroundColor Yellow
            Write-SecLog "WARN $Operation : $($_.Exception.Message)"
        }
    }

    function Export-WithSchema {
        param(
            [Parameter(Mandatory)] $Data,
            [Parameter(Mandatory)] [string] $OutPath
        )

        $schemaName = Resolve-AdSchemaNameForCsv -Path $OutPath
        if ([string]::IsNullOrWhiteSpace($schemaName)) {
            $Data | Export-AdCsvSafe -Path $OutPath -Force -AllowEmpty
        } else {
            $Data | Export-AdCsvSafe -Path $OutPath -SchemaName $schemaName -Force -AllowEmpty
        }
    }

    # ---------- Forest-level (ADCS) ----------
    if ($ForestDir -and (Test-Path -LiteralPath $ForestDir)) {

        Try-Export -Operation "ADCS Enterprise CAs (forest)" -Action {
            $cas = @(Get-AdSecurityAdcsInventory -Forest $Forest -Mode EnterpriseCAs)
            $out = Join-Path $ForestDir "AD__Forest__Security__ADCS__EnterpriseCAs__Forest.csv"
            Export-WithSchema -Data @($cas) -OutPath $out
        }

        Try-Export -Operation "ADCS Enrollment Services Templates (forest)" -Action {
            $map = @(Get-AdSecurityAdcsInventory -Forest $Forest -Mode EnrollmentServicesTemplates)
            $out = Join-Path $ForestDir "AD__Forest__Security__ADCS__EnrollmentServicesTemplates__Forest.csv"
            Export-WithSchema -Data @($map) -OutPath $out
        }

        Try-Export -Operation "ADCS Certificate Templates (forest)" -Action {
            $templates = @(Get-AdSecurityCertificateTemplates -Forest $Forest -Mode Templates)
            $out = Join-Path $ForestDir "AD__Forest__Security__ADCS__CertificateTemplates__Forest.csv"
            Export-WithSchema -Data @($templates) -OutPath $out
        }

        Try-Export -Operation "ADCS Certificate Template Permissions (forest)" -Action {
            $perms = @(Get-AdSecurityCertificateTemplates -Forest $Forest -Mode TemplatePermissions)
            $out = Join-Path $ForestDir "AD__Forest__Security__ADCS__CertificateTemplatePermissions__Forest.csv"
            Export-WithSchema -Data @($perms) -OutPath $out
        }
    }

    # ---------- Domain-level ----------
    if ($DomainContext -and $DomainDir -and (Test-Path -LiteralPath $DomainDir)) {

        Try-Export -Operation "Tier0 inventory (domain)" -Action {
            $tier0 = Get-AdSecurityTier0Inventory -DomainContext $DomainContext

            $out1 = Join-Path $DomainDir ("AD__Domain__Security__PrivilegedGroupMembers__{0}.csv" -f $ScopeTag)
            Export-WithSchema -Data @($tier0.PrivilegedGroupMembers) -OutPath $out1

            $out2 = Join-Path $DomainDir ("AD__Domain__Security__AdminCountObjects__{0}.csv" -f $ScopeTag)
            Export-WithSchema -Data @($tier0.AdminCountObjects) -OutPath $out2

            $out3 = Join-Path $DomainDir ("AD__Domain__Security__ProtectedUsers__{0}.csv" -f $ScopeTag)
            Export-WithSchema -Data @($tier0.ProtectedUsers) -OutPath $out3
        }

        Try-Export -Operation "Delegation inventory (domain)" -Action {
            $del = Get-AdSecurityDelegationInventory -DomainContext $DomainContext

            $outU = Join-Path $DomainDir ("AD__Domain__Security__DelegationUnconstrained__{0}.csv" -f $ScopeTag)
            Export-WithSchema -Data @($del.Unconstrained) -OutPath $outU

            $outC = Join-Path $DomainDir ("AD__Domain__Security__DelegationConstrained__{0}.csv" -f $ScopeTag)
            Export-WithSchema -Data @($del.Constrained) -OutPath $outC

            $outP = Join-Path $DomainDir ("AD__Domain__Security__DelegationProtocolTransition__{0}.csv" -f $ScopeTag)
            Export-WithSchema -Data @($del.ProtocolTransition) -OutPath $outP

            $outR = Join-Path $DomainDir ("AD__Domain__Security__DelegationRBCD__{0}.csv" -f $ScopeTag)
            Export-WithSchema -Data @($del.RBCD) -OutPath $outR
        }

        Try-Export -Operation "SPN Accounts inventory (domain)" -Action {
            $spn = @(Get-AdSecuritySpnAccounts -DomainContext $DomainContext)
            $out = Join-Path $DomainDir ("AD__Domain__Security__SpnAccounts__{0}.csv" -f $ScopeTag)
            Export-WithSchema -Data @($spn) -OutPath $out
        }

        Try-Export -Operation "Domain Controller security signals (best effort)" -Action {
            $signals = @(Get-AdSecurityDomainControllerSignals -DomainContext $DomainContext)
            $out = Join-Path $DomainDir ("AD__Domain__Security__DomainControllerSecuritySignals__{0}.csv" -f $ScopeTag)
            Export-WithSchema -Data @($signals) -OutPath $out
        }
    }
}

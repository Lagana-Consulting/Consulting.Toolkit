function Get-LcAdmtPasswordExportReadiness {
  [CmdletBinding()]
  param(
    # Source domain FQDN
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$SourceDomain,

    # Optional: specific DC to check (otherwise uses any available)
    [string]$SourceDC,

    # PES service name (default for ADMT)
    [string]$PesServiceName = 'PasswordExportServerSvc',

    # Check encryption certificate validity
    [switch]$CheckCertificate,

    [switch]$ThrowOnFailure
  )

  $messages = New-Object System.Collections.Generic.List[string]
  $warnings = New-Object System.Collections.Generic.List[string]

  # Determine DC to check
  $dcToCheck = if ($SourceDC) {
    $SourceDC
  } else {
    try {
      $dc = Get-ADDomainController -DomainName $SourceDomain -Discover -ErrorAction Stop
      $dc.HostName
    } catch {
      $messages.Add("Failed to locate DC for domain $SourceDomain`: $($_.Exception.Message)")
      $null
    }
  }

  $pesServiceFound = $false
  $pesServiceRunning = $false
  $pesServiceStatus = $null
  $dcReachable = $false
  $certificateValid = $null
  $certificateThumbprint = $null
  $certificateExpiry = $null

  if ($dcToCheck) {
    # Test DC connectivity
    try {
      $ping = Test-Connection -ComputerName $dcToCheck -Count 1 -Quiet -ErrorAction Stop
      $dcReachable = $ping
      if (-not $dcReachable) {
        $messages.Add("DC $dcToCheck is not reachable via ping")
      }
    } catch {
      $messages.Add("Failed to test connectivity to $dcToCheck`: $($_.Exception.Message)")
    }

    # Check PES service status (requires admin access to remote DC)
    if ($dcReachable) {
      try {
        $service = Get-Service -ComputerName $dcToCheck -Name $PesServiceName -ErrorAction Stop
        $pesServiceFound = $true
        $pesServiceRunning = $service.Status -eq 'Running'
        $pesServiceStatus = $service.Status

        if (-not $pesServiceRunning) {
          $messages.Add("PES service '$PesServiceName' exists on $dcToCheck but is not running (Status: $pesServiceStatus)")
        }
      } catch {
        if ($_.Exception.Message -match 'Cannot find any service') {
          $messages.Add("PES service '$PesServiceName' not found on $dcToCheck - Password Export Server may not be installed")
        } else {
          $warnings.Add("Could not query PES service on $dcToCheck - may require admin access: $($_.Exception.Message)")
          # Don't fail completely - service might exist but we lack permissions
        }
      }
    }

    # Check encryption certificate (if requested)
    if ($CheckCertificate -and $dcReachable) {
      try {
        # Look for PES certificate in remote registry or cert store
        # Simplification: check local machine cert store for PES-related certs
        $certPath = "\\$dcToCheck\c$\Windows\System32\config\systemprofile\AppData\Local\Microsoft\ADMT"

        if (Test-Path -LiteralPath $certPath -ErrorAction SilentlyContinue) {
          $warnings.Add("PES certificate path exists on $dcToCheck, but detailed validation requires additional tools")
        } else {
          $warnings.Add("Could not verify PES certificate path on $dcToCheck - manual verification recommended")
        }
      } catch {
        $warnings.Add("Certificate validation failed: $($_.Exception.Message)")
      }
    }
  }

  # Overall readiness assessment
  $passed = $dcReachable -and ($pesServiceFound -and $pesServiceRunning)

  # Build result object
  $result = [pscustomobject]@{
    SourceDomain           = $SourceDomain
    SourceDC               = $dcToCheck
    DCReachable            = $dcReachable
    PesServiceFound        = $pesServiceFound
    PesServiceRunning      = $pesServiceRunning
    PesServiceStatus       = $pesServiceStatus
    PesServiceName         = $PesServiceName
    CertificateValid       = $certificateValid
    CertificateThumbprint  = $certificateThumbprint
    CertificateExpiry      = $certificateExpiry
    Messages               = $messages.ToArray()
    Warnings               = $warnings.ToArray()
    Passed                 = $passed
  }

  if ($ThrowOnFailure -and -not $passed) {
    $detail = if ($messages.Count -gt 0) { $messages -join '; ' } else { 'Unknown failure' }
    throw "ADMT password export readiness check failed. $detail"
  }

  return $result
}

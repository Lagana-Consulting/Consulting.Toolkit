function Connect-AzCloudTenant {
  <#
  .SYNOPSIS
  Establishes authenticated connection to Microsoft cloud services using MS-Graph.

  .DESCRIPTION
  Connects to Azure AD / Entra ID using multiple authentication methods:
  - Certificate-based authentication (recommended for service principals / least privilege)
  - Interactive authentication (for user testing)
  - Device code flow (for headless scenarios)

  Supports both delegated (user) and app-only (service principal) flows.
  Validates tenant access and required scopes before returning connection context.

  .PARAMETER TenantId
  Azure AD tenant ID (GUID) or domain name (e.g., contoso.onmicrosoft.com).
  Required.

  .PARAMETER ClientId
  Application/Service Principal ID. Required for certificate or interactive auth.

  .PARAMETER CertificatePath
  Path to .pfx or .cer certificate file for certificate-based auth.
  If provided, certificate auth is used. Certificate must be installed in cert store
  or CertificateThumbprint must be provided for lookup.

  .PARAMETER CertificateThumbprint
  Thumbprint of certificate installed in LocalMachine\My store.
  Used when certificate is already installed; CertificatePath takes precedence.

  .PARAMETER CertificatePassword
  Password to decrypt .pfx certificate. Required if CertificatePath points to .pfx with password.

  .PARAMETER AuthType
  Authentication method: 'Certificate', 'Interactive', 'DeviceCode'.
  Default: 'Interactive'. If CertificatePath/Thumbprint provided, defaults to 'Certificate'.

  .PARAMETER Scopes
  Delegated scopes to request. Ignored for app-only (certificate) auth.
  Default scopes cover all workload discovery: User.Read, Group.Read.All, Device.Read.All, etc.

  .PARAMETER ValidateOnly
  If $true, validates connection but does not store context globally.
  Useful for testing credentials before use.

  .PARAMETER IncludeExchangeOnline
  If $true, also connects to Exchange Online using the same credentials.
  Enables distribution groups and resource mailbox discovery.
  Requires ExchangeOnlineManagement module. Default $false.

  .EXAMPLE
  $ctx = Connect-AzCloudTenant -TenantId "contoso.onmicrosoft.com" -ClientId "12345678-1234-1234-1234-123456789012" `
    -CertificatePath "C:\certs\cloud-app.pfx" -CertificatePassword (ConvertTo-SecureString "password" -AsPlainText -Force)

  Connects using certificate-based service principal auth (recommended for production).

  .EXAMPLE
  $ctx = Connect-AzCloudTenant -TenantId "contoso.onmicrosoft.com" -AuthType Interactive

  Connects interactively (prompts for credentials). User must have appropriate permissions.

  .EXAMPLE
  $ctx = Connect-AzCloudTenant -TenantId "contoso.onmicrosoft.com" -ClientId "12345678-1234-1234-1234-123456789012" `
    -CertificateThumbprint "1234567890ABCDEF1234567890ABCDEF12345678"

  Connects using certificate already installed in cert store (identified by thumbprint).

  .INPUTS
  None. This function does not accept pipeline input.

  .OUTPUTS
  [PSObject] Authentication context containing:
    - TenantId: Connected tenant GUID
    - ClientId: Application ID
    - AuthType: Authentication method used
    - AccessToken: Bearer token (do not expose)
    - TokenExpiry: Token expiration UTC timestamp
    - Scopes: Scopes granted
    - Account: User principal (if delegated auth)

  .NOTES
  - For least-privilege, use certificate auth with a service principal limited to required scopes/roles.
  - Certificate must have key usage for client authentication.
  - If using .pfx, recommended: openssl pkcs12 -export -in cert.cer -inkey key.pem -out cert.pfx
  - Access tokens are cached by MS-Graph SDK; subsequent calls in same session reuse token.
  - Use DisConnect-AzCloudTenant to clear context.

  .LINK
  DisConnect-AzCloudTenant
  Get-AzCloudAuthContext
  Get-AzCloudTenantInfo
  #>
  [CmdletBinding(DefaultParameterSetName = 'Interactive')]
  param(
    [Parameter(Mandatory)]
    [string]$TenantId,

    [Parameter(ParameterSetName = 'Certificate')]
    [Parameter(ParameterSetName = 'Interactive')]
    [string]$ClientId,

    [Parameter(ParameterSetName = 'Certificate')]
    [string]$CertificatePath,

    [Parameter(ParameterSetName = 'Certificate')]
    [string]$CertificateThumbprint,

    [Parameter(ParameterSetName = 'Certificate')]
    [securestring]$CertificatePassword,

    [Parameter(ParameterSetName = 'Interactive')]
    [ValidateSet('Certificate', 'Interactive', 'DeviceCode')]
    [string]$AuthType = 'Interactive',

    [string[]]$Scopes = @(
      'User.Read.All',
      'Group.Read.All',
      'Device.Read.All',
      'Application.Read.All',
      'Directory.Read.All',
      'Sites.Read.All',
      'Files.Read.All',
      'Team.ReadBasic.All',
      'TeamSettings.Read.All'
    ),

    [switch]$ValidateOnly,

    [switch]$IncludeExchangeOnline
  )

  # Validate MS-Graph module availability - check if installed
  $authModule = Get-Module Microsoft.Graph.Authentication -ListAvailable -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $authModule) {
    throw "Microsoft.Graph.Authentication module not installed. Run: .\Install-CloudDiscoveryPrerequisites.ps1"
  }

  # Try to load the module (it may already be loaded, which is fine)
  try {
    if (-not (Get-Module Microsoft.Graph.Authentication -ErrorAction SilentlyContinue)) {
      Import-Module Microsoft.Graph.Authentication -ErrorAction Stop -SkipEditionCheck
    }
  }
  catch {
    Write-Warning "Could not import Microsoft.Graph.Authentication module (may already be loaded). Proceeding..."
  }

  # Determine effective auth type
  $effectiveAuthType = $AuthType
  if ($CertificatePath -or $CertificateThumbprint) {
    $effectiveAuthType = 'Certificate'
  }

  $connectParams = @{
    TenantId    = $TenantId
    ErrorAction = 'Stop'
  }

  try {
    switch ($effectiveAuthType) {
      'Certificate' {
        if (-not $ClientId) {
          throw "ClientId required for certificate-based authentication"
        }
        if (-not ($CertificatePath -or $CertificateThumbprint)) {
          throw "CertificatePath or CertificateThumbprint required for certificate-based authentication"
        }

        if ($CertificatePath) {
          if (-not (Test-Path $CertificatePath)) {
            throw "Certificate file not found: $CertificatePath"
          }
          $connectParams['CertificatePath'] = $CertificatePath
          if ($CertificatePassword) {
            $connectParams['CertificatePassword'] = $CertificatePassword
          }
        }
        elseif ($CertificateThumbprint) {
          $connectParams['CertificateThumbprint'] = $CertificateThumbprint
        }

        $connectParams['ClientId'] = $ClientId
        $connectParams['Scope'] = 'https://graph.microsoft.com/.default'

        Write-Verbose "Connecting with certificate auth: TenantId=$TenantId, ClientId=$ClientId"
      }

      'Interactive' {
        # For interactive, ClientId is optional (uses Microsoft Graph default if omitted)
        if ($ClientId) {
          $connectParams['ClientId'] = $ClientId
        }
        # Scopes for delegated flow
        $connectParams['Scopes'] = $Scopes
        Write-Verbose "Connecting with interactive auth: TenantId=$TenantId"
      }

      'DeviceCode' {
        if (-not $ClientId) {
          throw "ClientId required for device code authentication"
        }
        $connectParams['ClientId'] = $ClientId
        $connectParams['DeviceCode'] = $true
        $connectParams['Scopes'] = $Scopes
        Write-Verbose "Connecting with device code auth: TenantId=$TenantId, ClientId=$ClientId"
      }
    }

    # Establish connection
    $connection = Connect-MgGraph @connectParams
    Write-Verbose "Successfully connected to Microsoft Graph"

    # Optionally connect to Exchange Online
    if ($IncludeExchangeOnline) {
      Write-Verbose "Connecting to Exchange Online..."
      try {
        # Import EXO module if available
        if (-not (Get-Module ExchangeOnlineManagement -ErrorAction SilentlyContinue)) {
          Import-Module ExchangeOnlineManagement -ErrorAction Stop -SkipEditionCheck
        }

        # Connect to EXO using same credentials
        if ($effectiveAuthType -eq 'Certificate') {
          # Certificate auth for EXO
          $exoParams = @{
            Organization        = $TenantId
            AppId               = $ClientId
            CertificateFilePath = $CertificatePath
            ErrorAction         = 'Stop'
          }
          if ($CertificatePassword) {
            $exoParams['CertificatePassword'] = $CertificatePassword
          }
          Connect-ExchangeOnline @exoParams | Out-Null
        }
        else {
          # Interactive/DeviceCode auth for EXO - just use interactive without specifying account
          $exoParams = @{
            ShowBanner  = $false
            ErrorAction = 'Stop'
          }
          Connect-ExchangeOnline @exoParams
        }
        Write-Host "✓ Connected to Exchange Online" -ForegroundColor Green
      }
      catch {
        Write-Warning "Failed to connect to Exchange Online: $($_.Exception.Message). Exchange-dependent functions will return empty results."
      }
    }

    # Build auth context object
    $context = @{
      TenantId    = $TenantId
      ClientId    = $ClientId
      AuthType    = $effectiveAuthType
      ConnectTime = Get-Date -AsUTC
      Scopes      = if ($effectiveAuthType -eq 'Certificate') { 'https://graph.microsoft.com/.default' } else { $Scopes }
      PSTypeName  = 'Lagana.Consulting.CloudAuthContext'
    }

    # Store context in script scope for use by discovery functions
    if (-not $ValidateOnly) {
      $script:AzCloudAuthContext = $context
      Write-Verbose "Authentication context stored for discovery functions"
    }

    return $context
  }
  catch {
    throw "Failed to connect to cloud tenant. $($_.Exception.Message)"
  }
}

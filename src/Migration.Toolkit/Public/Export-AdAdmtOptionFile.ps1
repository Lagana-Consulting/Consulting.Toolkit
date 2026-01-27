function Export-AdAdmtOptionFile {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Path,

    # High-level toggles (leave defaults conservative)
    [switch]$MigrateSIDs,
    [switch]$UpdateUserRights,
    [switch]$TranslateRoamingProfiles,
    [switch]$TranslateLocalProfiles,

    # Password option (only if you have PES / strategy in place)
    [switch]$MigratePasswords,

    # Behavior
    [ValidateSet('Fail','Rename')]
    [string]$NameConflictBehavior = 'Fail',

    [switch]$Force
  )

  $outPath = Resolve-AdPath -Path $Path
  $parent = Split-Path -Path $outPath -Parent
  if ($parent) { New-AdDirectory -Path $parent | Out-Null }

  if ((Test-Path -LiteralPath $outPath) -and -not $Force) {
    throw "File already exists: $outPath (use -Force to overwrite)"
  }

  $lines = New-Object System.Collections.Generic.List[string]

  # NOTE: ADMT option keys vary by object type and version.
  # This file is a practical starting template; tune keys to your ADMT standard.
  $lines.Add('[Migration]')
  $lines.Add(('MigrateSIDs={0}' -f ($(if ($MigrateSIDs) { 'Yes' } else { 'No' }))))
  $lines.Add(('MigratePasswords={0}' -f ($(if ($MigratePasswords) { 'Yes' } else { 'No' }))))
  $lines.Add(('NameConflictBehavior={0}' -f $NameConflictBehavior))
  $lines.Add('')

  $lines.Add('[Security]')
  $lines.Add(('UpdateUserRights={0}' -f ($(if ($UpdateUserRights) { 'Yes' } else { 'No' }))))
  $lines.Add('')

  $lines.Add('[Profiles]')
  $lines.Add(('TranslateRoamingProfiles={0}' -f ($(if ($TranslateRoamingProfiles) { 'Yes' } else { 'No' }))))
  $lines.Add(('TranslateLocalProfiles={0}' -f ($(if ($TranslateLocalProfiles) { 'Yes' } else { 'No' }))))
  $lines.Add('')

  $lines.Add('[Notes]')
  $lines.Add('; Review and adjust ADMT options to match your migration runbook.')
  $lines.Add('; Keep this file per-wave if different options are required.')
  $lines.Add('')

  # Write as ASCII to be safest with older tooling (ADMT-era), but UTF8 is usually fine too.
  Set-Content -Path $outPath -Value $lines -Encoding ASCII -Force

  return $outPath
}

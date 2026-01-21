function Get-LcGroupMembersRecursive {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$GroupDn,
    [Parameter(Mandatory)][string]$Server
  )

  if (-not (Get-Command Get-ADGroupMember -ErrorAction SilentlyContinue)) {
    throw "ActiveDirectory module not available (Get-ADGroupMember missing)."
  }

  $seenGroups = @{}
  $results = @()

  $stack = New-Object System.Collections.Generic.Stack[string]
  $stack.Push($GroupDn)

  while ($stack.Count -gt 0) {
    $current = $stack.Pop()
    if ($seenGroups.ContainsKey($current)) { continue }
    $seenGroups[$current] = $true

    $members = @()
    try {
      $members = @(Get-ADGroupMember -Identity $current -Server $Server -ErrorAction Stop)
    } catch {
      continue
    }

    foreach ($m in $members) {
      if ($m.objectClass -eq 'group') {
        $stack.Push([string]$m.DistinguishedName)
      } elseif ($m.objectClass -eq 'user') {
        $results += $m
      }
    }
  }

  return @($results)
}

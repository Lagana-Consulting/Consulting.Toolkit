[CmdletBinding()]
param([ValidateRange(1,1000000)][int[]]$RowCounts = @(10000))
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$module = Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'Consulting.Toolkit.Discovery.psd1') -Force -PassThru -WarningAction SilentlyContinue
$root = Join-Path ([IO.Path]::GetTempPath()) ('AdDiscoveryPerformance-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null

& $module {
    param($Root, $Counts)
    function Assert-Performance {
        param([bool]$Condition, [string]$Message)
        if (-not $Condition) { throw "Assertion failed: $Message" }
    }
    $path = Join-Path $Root 'Streaming [literal].csv'
    [pscustomobject]@{Name='Original';Description='Keep me'} | Export-AdCsvSafe -Path $path -Force | Out-Null
    $protectedAcl = Get-Acl -LiteralPath $path
    $protectedAcl.SetAccessRuleProtection($true, $true)
    Set-Acl -LiteralPath $path -AclObject $protectedAcl
    $originalAcl = (Get-Acl -LiteralPath $path).Sddl
    $originalHash = (Get-FileHash -LiteralPath $path).Hash
    $state = @{ Staged=$false; SourceDone=$false }
    function New-StreamingRows {
        for ($i=1; $i -le 1000; $i++) {
            if ($i -eq 257) {
                $partials = @(Get-ChildItem -LiteralPath $Root -Force -Filter '*.partial')
                Assert-Performance ($partials.Count -eq 1 -and $partials[0].Length -gt 0) 'CSV writes while source enumeration is still running'
                Assert-Performance ((Get-FileHash -LiteralPath $path).Hash -eq $originalHash) 'Destination remains intact until completion'
                $state.Staged=$true
            }
            [pscustomobject]@{Name="Row$i";Description="Comma, `"quoted`"`nUnicode caf$([char]0xe9)"}
        }
        $state.SourceDone=$true
    }
    New-StreamingRows | Export-AdCsvSafe -Path $path -Force | Out-Null
    $rows = @(Import-Csv -LiteralPath $path)
    Assert-Performance ($state.Staged -and $state.SourceDone -and $rows.Count -eq 1000) 'All streaming rows published'
    Assert-Performance ($rows[0].Description -eq "Comma, `"quoted`"`nUnicode caf$([char]0xe9)" -and $rows[999].Name -eq 'Row1000') 'Quoting, Unicode, and order cross batch boundaries'
    Assert-Performance ((Get-Acl -LiteralPath $path).Sddl -eq $originalAcl) 'Atomic replacement preserves destination ACLs'
    Assert-Performance (@(Get-ChildItem -LiteralPath $Root -Force -Filter '*.partial').Count -eq 0) 'Successful publication removes staging file'

    $originalHash = (Get-FileHash -LiteralPath $path).Hash
    $failed=$false
    try {
        & {
            for ($i=1; $i -le 900; $i++) {
                if ($i -eq 900) { [pscustomobject]@{Name='Missing columns'} } else {
                    [pscustomobject]@{Name="Site$i";DistinguishedName="CN=Site$i";Description=''}
                }
            }
        } | Export-AdCsvSafe -Path $path -SchemaName Forest_Sites -Force | Out-Null
    } catch { $failed=$_.Exception.Message -like '*missing column*' }
    Assert-Performance ($failed -and (Get-FileHash -LiteralPath $path).Hash -eq $originalHash) 'Late schema failure cannot overwrite existing CSV'
    Assert-Performance (@(Get-ChildItem -LiteralPath $Root -Force -Filter '*.partial').Count -eq 0) 'Late schema failure removes staging file'

    # PowerShell 5.1 has no clean block: interrupted producers may leave an
    # unpublished .partial file, but must leave no open writer or finalized CSV.
    $failed=$false
    try {
        & {
            for ($i=1; $i -le 600; $i++) {
                if ($i -eq 600) { throw 'Simulated upstream failure' }
                [pscustomobject]@{Name="Upstream$i"}
            }
        } | Export-AdCsvSafe -Path $path -Force | Out-Null
    } catch { $failed=$_.Exception.Message -like '*upstream failure*' }
    Assert-Performance ($failed -and (Get-FileHash -LiteralPath $path).Hash -eq $originalHash) 'Producer failure cannot publish partial rows'
    foreach ($partial in @(Get-ChildItem -LiteralPath $Root -Force -Filter '*.partial')) {
        $handle = [IO.File]::Open($partial.FullName,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        $handle.Dispose()
        Remove-Item -LiteralPath $partial.FullName -Force
    }

    $racePath = Join-Path $Root 'Concurrent.csv'
    $failed=$false
    try {
        & {
            [pscustomobject]@{Name='Attempt'}
            [IO.File]::WriteAllText($racePath,'Concurrent writer')
        } | Export-AdCsvSafe -Path $racePath | Out-Null
    } catch { $failed=$_.Exception.Message -like '*already exists*' }
    Assert-Performance ($failed -and [IO.File]::ReadAllText($racePath) -eq 'Concurrent writer') 'Concurrent destination creation honors absence of Force'
    Write-Host 'PASS: streaming before source completion, late validation, interrupted producers, literal paths, and concurrent publication'

    # Query fixtures exercise the actual collectors; predicates must be sent to AD.
    $ctx = [pscustomobject]@{DomainFqdn='example.test';DomainDn='DC=example,DC=test';Server='dc.example.test'}
    function Get-ADObject {
        [CmdletBinding()] param($LDAPFilter,$SearchBase,$SearchScope,$Server,$Properties)
        Assert-Performance ($LDAPFilter -eq '(&(|(objectClass=user)(objectClass=computer))(servicePrincipalName=*))') 'SPN presence pushed into AD filter'
        Assert-Performance ($SearchBase -eq $ctx.DomainDn -and $Server -eq $ctx.Server) 'SPNs preserve domain and DC targeting'
        [pscustomobject]@{ObjectClass='user';servicePrincipalName=@('HTTP/a','HTTP/b');sAMAccountName='service';DistinguishedName='CN=service,DC=example,DC=test'}
    }
    function Get-ADUser {
        [CmdletBinding()] param($LDAPFilter,$SearchBase,$SearchScope,$Server,$Properties)
        Assert-Performance ($LDAPFilter -eq '(sIDHistory=*)' -and $Server -eq $ctx.Server -and $SearchBase -eq $ctx.DomainDn) 'SID presence filter preserves target'
        [pscustomobject]@{SamAccountName='migrated';DistinguishedName='CN=migrated,DC=example,DC=test';SIDHistory=@('S-1-5-21-1','S-1-5-21-2')}
    }
    $spns = @(Get-AdAdSpns -DomainContext $ctx)
    $sids = @(Get-AdUsersSidHistory -DomainContext $ctx)
    Assert-Performance ($spns.Count -eq 2 -and $spns[0].ServicePrincipalName -eq 'HTTP/a' -and $spns[1].SPN -eq 'HTTP/b') 'SPN raw values and aliases retained'
    Assert-Performance ($sids.Count -eq 2 -and $sids[1].SidHistory -eq 'S-1-5-21-2') 'Each SID-history value retained'
    Write-Host 'PASS: narrower SPN and SID-history queries preserve multi-valued output and target integrity'

    # Substitute only socket construction to simulate a connection that never
    # completes, and verify the real wait and disposal behavior without WAN access.
    $socketState = @{Closed=$false}
    $pending = [System.Threading.Tasks.TaskCompletionSource[bool]]::new()
    $fakeClient = [pscustomobject]@{Connected=$false;Pending=$pending;State=$socketState}
    $fakeClient | Add-Member ScriptMethod ConnectAsync { param($HostName,$Port); return $this.Pending.Task }
    $fakeClient | Add-Member ScriptMethod Close { $this.State.Closed=$true }
    function New-Object {
        param([string]$TypeName,[object[]]$ArgumentList)
        if ($TypeName -eq 'System.Net.Sockets.TcpClient') { return $fakeClient }
        Microsoft.PowerShell.Utility\New-Object @PSBoundParameters
    }
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $reachable = Test-AdTcpPort -ComputerName 'not-queried.example.test' -Port 9389 -TimeoutMs 30
    $timer.Stop()
    Assert-Performance (-not $reachable -and $socketState.Closed -and $timer.ElapsedMilliseconds -lt 1500) 'Pending socket is bounded and disposed'
    $fakeClient.Connected=$true; $socketState.Closed=$false; $pending.SetResult($true)
    $reachable = @(Test-AdTcpPort -ComputerName 'not-queried.example.test' -Port 9389 -TimeoutMs 30)
    Assert-Performance ($reachable.Count -eq 1 -and $reachable[0] -eq $true -and $socketState.Closed) 'Completed connection returns one Boolean and disposes socket'
    Remove-Item Function:\New-Object

    $probeState = @{Calls=New-Object System.Collections.Generic.List[object];Mode='Select'}
    function Get-ADDomainController {
        [CmdletBinding()] param($Filter,$Server)
        [pscustomobject]@{HostName='rodc.example.test';IsReadOnly=$true;IsPdc=$true;IsGlobalCatalog=$true}
        [pscustomobject]@{HostName='first.example.test';IsReadOnly=$false;IsPdc=$true;IsGlobalCatalog=$true}
        [pscustomobject]@{HostName='second.example.test';IsReadOnly=$false;IsPdc=$false;IsGlobalCatalog=$true}
        [pscustomobject]@{HostName='third.example.test';IsReadOnly=$false;IsPdc=$false;IsGlobalCatalog=$false}
    }
    function Test-AdTcpPort {
        param($ComputerName,$Port,$TimeoutMs)
        $probeState.Calls.Add([pscustomobject]@{HostName=$ComputerName;Port=$Port;TimeoutMs=$TimeoutMs})
        if ($probeState.Mode -eq 'Budget') { Start-Sleep -Milliseconds $TimeoutMs; return $false }
        return $ComputerName -eq 'second.example.test'
    }
    $selected = Get-AdWritableDc -DomainFqdn example.test -TimeoutMs 100 -ProbeBudgetMs 1000
    Assert-Performance ($selected -eq 'second.example.test' -and $probeState.Calls.Count -eq 2) "Writable reachable candidate selected (selected=$selected; calls=$($probeState.Calls.Count))"
    Assert-Performance (@($probeState.Calls | Where-Object Port -ne 9389).Count -eq 0) 'Selection probes ADWS'
    $probeState.Calls.Clear(); $probeState.Mode='Budget'
    $timer.Restart()
    $selected = Get-AdWritableDc -DomainFqdn example.test -TimeoutMs 100 -ProbeBudgetMs 35
    $timer.Stop()
    Assert-Performance ($selected -eq 'example.test' -and $probeState.Calls.Count -eq 1 -and $probeState.Calls[0].TimeoutMs -le 35 -and $timer.ElapsedMilliseconds -lt 1500) 'Total probe budget limits candidates and retains explicit domain fallback'
    Write-Host 'PASS: socket deadline/disposal, writable ADWS selection, and total connectivity-probe budget'

    foreach ($count in $Counts) {
        $output = Join-Path $Root ("Scale$count.csv")
        $timer.Restart()
        & {
            for ($i=1; $i -le $count; $i++) {
                [pscustomobject]@{Name="Object$i";Description='Scale test';Date=[datetime]::new(2025,4,3,13,30,0,[DateTimeKind]::Utc)}
            }
        } | Export-AdCsvSafe -Path $output | Out-Null
        $timer.Stop()
        $importCount=0; $lastName=''
        Import-Csv -LiteralPath $output | ForEach-Object { $importCount++; $lastName=$_.Name }
        Assert-Performance ($importCount -eq $count -and $lastName -eq "Object$count") "$count rows retain count and ordering"
        $process = [Diagnostics.Process]::GetCurrentProcess()
        Write-Host ('PASS: {0} streamed rows; export={1:n2}s; process peak working set={2:n1} MB; bytes={3}' -f $count,$timer.Elapsed.TotalSeconds,($process.PeakWorkingSet64/1MB),(Get-Item -LiteralPath $output).Length)
    }
    Write-Host "Performance outputs: $Root"
} $root $RowCounts

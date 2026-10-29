function Test-AdTcpPort {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][ValidateRange(1,65535)][int]$Port,
        [ValidateRange(1,60000)][int]$TimeoutMs = 1500
    )
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        # Includes asynchronous name resolution and connection establishment.
        $connect = $client.ConnectAsync($ComputerName, $Port)
        if (-not $connect.Wait($TimeoutMs)) { return $false }
        [void]$connect.GetAwaiter().GetResult()
        return $client.Connected
    } catch {
        return $false
    } finally {
        $client.Close()
    }
}

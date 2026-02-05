namespace Collector.Graph;

public sealed record TokenInfo(
    string AccessToken,
    string[] GrantedScopes,
    string UserPrincipalName,
    string TenantId,
    DateTimeOffset ExpiresOn,
    AuthMode AuthMode
)
{
    // Alias for backwards compatibility
    public string Username => UserPrincipalName;
}

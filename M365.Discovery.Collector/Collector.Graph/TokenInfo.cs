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
    public string? AuthenticationPath { get; init; }
    public string[] DelegatedScopes { get; init; } = Array.Empty<string>();
    public string[] ApplicationRoles { get; init; } = Array.Empty<string>();
    public string[] GrantedPermissions { get; init; } = Array.Empty<string>();
}

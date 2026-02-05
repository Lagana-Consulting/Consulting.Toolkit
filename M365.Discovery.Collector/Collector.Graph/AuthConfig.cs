namespace Collector.Graph;

public sealed class AuthConfig
{
    public required string ClientId { get; init; }
    public string? TenantId { get; init; }
    public string? ClientSecret { get; init; }
    public required AuthMode Mode { get; init; }
    public string[] DelegatedScopes { get; init; } = Array.Empty<string>();

    public static AuthConfig CreateAppOnly(string clientId, string tenantId, string clientSecret)
    {
        return new AuthConfig
        {
            ClientId = clientId,
            TenantId = tenantId,
            ClientSecret = clientSecret,
            Mode = AuthMode.AppOnly
        };
    }

    public static AuthConfig CreateDelegated(string clientId, string? tenantId = null)
    {
        return new AuthConfig
        {
            ClientId = clientId,
            TenantId = tenantId,
            Mode = AuthMode.InteractiveDelegated,
            DelegatedScopes = new[]
            {
                "User.Read.All",
                "Group.Read.All",
                "Application.Read.All",
                "Directory.Read.All",
                "Reports.Read.All",
                "Organization.Read.All",
                "Domain.Read.All"
            }
        };
    }
}

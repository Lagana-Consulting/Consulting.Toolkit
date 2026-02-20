namespace Collector.Graph;

public sealed class AuthConfig
{
    public required string ClientId { get; init; }
    public string? TenantId { get; init; }
    public string? ClientSecret { get; init; }
    public string? CertificateThumbprint { get; init; }
    public string? CertificateSubjectName { get; init; }
    public bool AllowClientSecretFallback { get; init; }
    public required AuthMode Mode { get; init; }
    public string[] DelegatedScopes { get; init; } = Array.Empty<string>();

    public static AuthConfig CreateAppOnly(string clientId, string tenantId, string clientSecret)
    {
        return new AuthConfig
        {
            ClientId = clientId,
            TenantId = tenantId,
            ClientSecret = clientSecret,
            AllowClientSecretFallback = true,
            Mode = AuthMode.AppOnly
        };
    }

    public static AuthConfig CreateAppOnlyWithCertificateByThumbprint(string clientId, string tenantId, string certificateThumbprint)
    {
        return new AuthConfig
        {
            ClientId = clientId,
            TenantId = tenantId,
            CertificateThumbprint = certificateThumbprint,
            Mode = AuthMode.AppOnly
        };
    }

    public static AuthConfig CreateAppOnlyWithCertificateBySubject(string clientId, string tenantId, string certificateSubjectName)
    {
        return new AuthConfig
        {
            ClientId = clientId,
            TenantId = tenantId,
            CertificateSubjectName = certificateSubjectName,
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

    public void Validate()
    {
        if (string.IsNullOrWhiteSpace(ClientId))
        {
            throw new InvalidOperationException("ClientId is required.");
        }

        if (Mode == AuthMode.InteractiveDelegated)
        {
            return;
        }

        if (string.IsNullOrWhiteSpace(TenantId))
        {
            throw new InvalidOperationException("TenantId is required for app-only authentication.");
        }

        var hasSecret = !string.IsNullOrWhiteSpace(ClientSecret);
        var hasThumbprint = !string.IsNullOrWhiteSpace(CertificateThumbprint);
        var hasSubject = !string.IsNullOrWhiteSpace(CertificateSubjectName);
        var hasCertificate = hasThumbprint || hasSubject;

        if (hasThumbprint && hasSubject)
        {
            throw new InvalidOperationException(
                "App-only configuration is invalid: set either CertificateThumbprint or CertificateSubjectName, not both.");
        }

        if (hasSecret && hasCertificate)
        {
            throw new InvalidOperationException(
                "App-only configuration is invalid: provide either client secret fallback or certificate settings, not both.");
        }

        if (!hasSecret && !hasCertificate)
        {
            throw new InvalidOperationException(
                "App-only configuration is invalid: provide certificate settings (recommended) or enable client secret fallback.");
        }

        if (hasSecret && !AllowClientSecretFallback)
        {
            throw new InvalidOperationException(
                "Client secret is configured but client secret fallback is disabled. Set AllowClientSecretFallback=true to permit secret auth.");
        }
    }
}

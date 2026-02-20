using Microsoft.Graph;
using Microsoft.Identity.Client;
using System.Diagnostics;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Cryptography.X509Certificates;

namespace Collector.Graph.Auth;

public class GraphClientFactory
{
    private readonly AuthConfig _config;
    private const string GraphDefaultScope = "https://graph.microsoft.com/.default";

    public GraphClientFactory(AuthConfig config)
    {
        _config = config;
        _config.Validate();
    }

    public async Task<(GraphServiceClient Client, TokenInfo TokenInfo)> CreateAuthenticatedClientAsync()
    {
        GraphServiceClient client;
        TokenInfo tokenInfo;

        if (_config.Mode == AuthMode.InteractiveDelegated)
        {
            Trace.WriteLine($"[AUTH] mode=InteractiveDelegated authorityTenant={_config.TenantId ?? "common"}");

            var pca = PublicClientApplicationBuilder
                .Create(_config.ClientId)
                .WithAuthority(AzureCloudInstance.AzurePublic, _config.TenantId ?? "common")
                .WithRedirectUri("http://localhost")
                .Build();

            AuthenticationResult authResult;
            try
            {
                var accounts = await pca.GetAccountsAsync();
                authResult = await pca.AcquireTokenSilent(_config.DelegatedScopes, accounts.FirstOrDefault())
                    .ExecuteAsync();
            }
            catch (MsalUiRequiredException)
            {
                authResult = await pca.AcquireTokenInteractive(_config.DelegatedScopes)
                    .ExecuteAsync();
            }

            var authProvider = new DelegateAuthenticationProvider(async (request) =>
            {
                request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", authResult.AccessToken);
            });

            client = new GraphServiceClient(authProvider);
            var me = await client.Me.Request().GetAsync();
            var tokenPermissions = ExtractTokenPermissions(authResult.AccessToken);
            var delegatedScopes = authResult.Scopes?
                .Concat(tokenPermissions.DelegatedScopes)
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToArray() ?? tokenPermissions.DelegatedScopes;
            var grantedPermissions = delegatedScopes
                .Concat(tokenPermissions.ApplicationRoles)
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToArray();
             
            tokenInfo = new TokenInfo(
                authResult.AccessToken,
                grantedPermissions,
                me?.UserPrincipalName ?? authResult.Account?.Username ?? "Unknown",
                authResult.TenantId ?? "Unknown",
                authResult.ExpiresOn,
                _config.Mode
            )
            {
                AuthenticationPath = "delegated_interactive",
                DelegatedScopes = delegatedScopes,
                ApplicationRoles = tokenPermissions.ApplicationRoles,
                GrantedPermissions = grantedPermissions
            };
        }
        else
        {
            var authority = new Uri($"https://login.microsoftonline.com/{_config.TenantId}");
            var ccaBuilder = ConfidentialClientApplicationBuilder
                .Create(_config.ClientId)
                .WithAuthority(authority);

            var authPath = string.Empty;
            if (!string.IsNullOrWhiteSpace(_config.CertificateThumbprint))
            {
                var cert = FindCertificateByThumbprint(_config.CertificateThumbprint);
                ccaBuilder = ccaBuilder.WithCertificate(cert);
                authPath = "certificate_thumbprint";
            }
            else if (!string.IsNullOrWhiteSpace(_config.CertificateSubjectName))
            {
                var cert = FindCertificateBySubjectName(_config.CertificateSubjectName);
                ccaBuilder = ccaBuilder.WithCertificate(cert);
                authPath = "certificate_subject";
            }
            else if (_config.AllowClientSecretFallback && !string.IsNullOrWhiteSpace(_config.ClientSecret))
            {
                ccaBuilder = ccaBuilder.WithClientSecret(_config.ClientSecret);
                authPath = "client_secret_fallback";
            }
            else
            {
                throw new InvalidOperationException(
                    "App-only authentication could not determine a valid credential path. Configure certificate auth or explicitly enable client secret fallback.");
            }

            Trace.WriteLine($"[AUTH] mode=AppOnly authPath={authPath} tenant={_config.TenantId}");

            var cca = ccaBuilder.Build();

            var authResult = await cca.AcquireTokenForClient(new[] { GraphDefaultScope })
                .ExecuteAsync();

            var authProvider = new DelegateAuthenticationProvider(async (request) =>
            {
                request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", authResult.AccessToken);
            });

            client = new GraphServiceClient(authProvider);
            var tokenPermissions = ExtractTokenPermissions(authResult.AccessToken);
            var grantedPermissions = tokenPermissions.GrantedPermissions.Length > 0
                ? tokenPermissions.GrantedPermissions
                : new[] { GraphDefaultScope };

            tokenInfo = new TokenInfo(
                authResult.AccessToken,
                grantedPermissions,
                "Service Principal",
                _config.TenantId ?? "Unknown",
                authResult.ExpiresOn,
                _config.Mode
            )
            {
                AuthenticationPath = authPath,
                DelegatedScopes = tokenPermissions.DelegatedScopes,
                ApplicationRoles = tokenPermissions.ApplicationRoles,
                GrantedPermissions = grantedPermissions
            };
        }

        return (client, tokenInfo);
    }

    private static X509Certificate2 FindCertificateByThumbprint(string thumbprint)
    {
        var normalized = thumbprint.Replace(" ", string.Empty).ToUpperInvariant();
        foreach (var location in new[] { StoreLocation.CurrentUser, StoreLocation.LocalMachine })
        {
            using var store = new X509Store(StoreName.My, location);
            store.Open(OpenFlags.ReadOnly);
            var matches = store.Certificates.Find(X509FindType.FindByThumbprint, normalized, validOnly: false);
            var cert = matches.Cast<X509Certificate2>().FirstOrDefault(c => c.HasPrivateKey);
            if (cert != null)
            {
                return cert;
            }
        }

        throw new InvalidOperationException(
            $"Certificate not found by thumbprint '{thumbprint}' in CurrentUser/My or LocalMachine/My with an accessible private key.");
    }

    private static X509Certificate2 FindCertificateBySubjectName(string subjectName)
    {
        foreach (var location in new[] { StoreLocation.CurrentUser, StoreLocation.LocalMachine })
        {
            using var store = new X509Store(StoreName.My, location);
            store.Open(OpenFlags.ReadOnly);
            var matches = store.Certificates.Find(X509FindType.FindBySubjectName, subjectName, validOnly: false);
            var cert = matches.Cast<X509Certificate2>().FirstOrDefault(c => c.HasPrivateKey);
            if (cert != null)
            {
                return cert;
            }
        }

        throw new InvalidOperationException(
            $"Certificate not found by subject '{subjectName}' in CurrentUser/My or LocalMachine/My with an accessible private key.");
    }

    private static (string[] DelegatedScopes, string[] ApplicationRoles, string[] GrantedPermissions) ExtractTokenPermissions(string accessToken)
    {
        try
        {
            var handler = new JwtSecurityTokenHandler();
            var token = handler.ReadJwtToken(accessToken);

            var delegated = token.Claims
                .Where(c => c.Type.Equals("scp", StringComparison.OrdinalIgnoreCase))
                .SelectMany(c => c.Value.Split(' ', StringSplitOptions.RemoveEmptyEntries))
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToArray();

            var roles = token.Claims
                .Where(c =>
                    c.Type.Equals("roles", StringComparison.OrdinalIgnoreCase) ||
                    c.Type.EndsWith("/claims/role", StringComparison.OrdinalIgnoreCase))
                .SelectMany(c => c.Value.Split(new[] { ' ', ',' }, StringSplitOptions.RemoveEmptyEntries))
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToArray();

            var all = delegated
                .Concat(roles)
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToArray();

            return (delegated, roles, all);
        }
        catch (Exception ex)
        {
            Trace.WriteLine($"[AUTH] token-claims-parse-failed message={ex.Message}");
            return (Array.Empty<string>(), Array.Empty<string>(), Array.Empty<string>());
        }
    }
}

using Microsoft.Graph;
using Microsoft.Identity.Client;

namespace Collector.Graph.Auth;

public class GraphClientFactory
{
    private readonly AuthConfig _config;

    public GraphClientFactory(AuthConfig config)
    {
        _config = config;
    }

    public async Task<(GraphServiceClient Client, TokenInfo TokenInfo)> CreateAuthenticatedClientAsync()
    {
        GraphServiceClient client;
        TokenInfo tokenInfo;

        if (_config.Mode == AuthMode.InteractiveDelegated)
        {
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
            
            tokenInfo = new TokenInfo(
                authResult.AccessToken,
                authResult.Scopes?.ToArray() ?? Array.Empty<string>(),
                me?.UserPrincipalName ?? authResult.Account?.Username ?? "Unknown",
                authResult.TenantId ?? "Unknown",
                authResult.ExpiresOn,
                _config.Mode
            );
        }
        else
        {
            var cca = ConfidentialClientApplicationBuilder
                .Create(_config.ClientId)
                .WithClientSecret(_config.ClientSecret)
                .WithAuthority(new Uri($"https://login.microsoftonline.com/{_config.TenantId}"))
                .Build();

            var authResult = await cca.AcquireTokenForClient(new[] { "https://graph.microsoft.com/.default" })
                .ExecuteAsync();

            var authProvider = new DelegateAuthenticationProvider(async (request) =>
            {
                request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", authResult.AccessToken);
            });

            client = new GraphServiceClient(authProvider);

            tokenInfo = new TokenInfo(
                authResult.AccessToken,
                new[] { "https://graph.microsoft.com/.default" },
                "Service Principal",
                _config.TenantId ?? "Unknown",
                authResult.ExpiresOn,
                _config.Mode
            );
        }

        return (client, tokenInfo);
    }
}
using Microsoft.Graph;

namespace Collector.Graph;

/// <summary>
/// Wraps GraphServiceClient with resilience: retry, throttling, paging
/// </summary>
public sealed class ResilientGraphClient
{
    private readonly GraphServiceClient _client;
    private readonly SemaphoreSlim _rateLimiter;

    public ResilientGraphClient(GraphServiceClient client, int maxParallelRequests = 4)
    {
        _client = client ?? throw new ArgumentNullException(nameof(client));
        _rateLimiter = new SemaphoreSlim(maxParallelRequests, maxParallelRequests);
    }

    public GraphServiceClient Client => _client;

    /// <summary>
    /// Execute a Graph request with retry + rate limiting
    /// </summary>
    public async Task<T> ExecuteAsync<T>(Func<GraphServiceClient, Task<T>> graphCall, CancellationToken cancellationToken = default)
    {
        await _rateLimiter.WaitAsync(cancellationToken);
        try
        {
            return await graphCall(_client);
        }
        finally
        {
            _rateLimiter.Release();
        }
    }

    /// <summary>
    /// Page through all results from a Graph collection (Microsoft Graph SDK v4)
    /// </summary>
    public async IAsyncEnumerable<TEntity> PageAllAsync<TEntity, TCollectionPage>(
        Func<GraphServiceClient, Task<TCollectionPage>> getFirstPage,
        [System.Runtime.CompilerServices.EnumeratorCancellation] CancellationToken cancellationToken = default)
        where TCollectionPage : ICollectionPage<TEntity>
    {
        TCollectionPage? page = await ExecuteAsync(getFirstPage, cancellationToken);

        while (page != null && page.Count > 0)
        {
            foreach (var item in page)
            {
                yield return item;
            }

            // Use dynamic to access NextPageRequest since it's not part of ICollectionPage<T>
            var nextPageRequest = (page as dynamic)?.NextPageRequest;
            if (nextPageRequest == null)
                break;

            await _rateLimiter.WaitAsync(cancellationToken);
            try
            {
                page = await nextPageRequest.GetAsync(cancellationToken);
            }
            finally
            {
                _rateLimiter.Release();
            }
        }
    }
}
using Amazon;
using Amazon.Runtime;
using OpenSearch.Client;
using OpenSearch.Net;
using QALambda.Models;
using System.Text.Json;

namespace QALambda.Services;

public class OpenSearchService
{
    private readonly OpenSearchClient _client;
    private readonly string _indexName = "sports-handbooks";

    public OpenSearchService(string endpoint, string region)
    {
        var credentials = FallbackCredentialsFactory.GetCredentials();
        var httpConnection = new AwsHttpConnection(credentials, RegionEndpoint.GetBySystemName(region));
        
        var connectionPool = new SingleNodeConnectionPool(new Uri($"https://{endpoint}"));
        var settings = new ConnectionSettings(connectionPool, httpConnection)
            .DefaultIndex(_indexName)
            .DisableDirectStreaming();

        _client = new OpenSearchClient(settings);
    }

    public async Task<List<SearchResult>> SearchDocumentsAsync(string query, int maxResults = 5)
    {
        try
        {
            // First, get embedding for the query (we'll use a simple text search for now)
            // In production, you'd want to call your embedding service here
            
            var searchResponse = await _client.SearchAsync<dynamic>(s => s
                .Index(_indexName)
                .Size(maxResults)
                .Query(q => q
                    .Bool(b => b
                        .Should(
                            // Text-based search
                            sh => sh.Match(m => m
                                .Field("text")
                                .Query(query)
                                .Boost(1.0)
                            ),
                            // Add more query types as needed
                            sh => sh.MultiMatch(mm => mm
                                .Fields(f => f.Field("text").Field("metadata.document_type"))
                                .Query(query)
                                .Boost(0.5)
                            )
                        )
                    )
                )
                .Source(src => src
                    .Includes(i => i
                        .Field("text")
                        .Field("source")
                        .Field("metadata")
                        .Field("chunk_index")
                    )
                )
            );

            if (!searchResponse.IsValid)
            {
                Console.WriteLine($"OpenSearch query failed: {searchResponse.OriginalException?.Message}");
                return new List<SearchResult>();
            }

            var results = new List<SearchResult>();
            
            foreach (var hit in searchResponse.Documents)
            {
                var hitDict = hit as IDictionary<string, object>;
                if (hitDict != null)
                {
                    var result = new SearchResult
                    {
                        Score = searchResponse.Hits.FirstOrDefault(h => h.Source.Equals(hit))?.Score ?? 0,
                        Text = hitDict.GetValueOrDefault("text")?.ToString() ?? "",
                        Source = hitDict.GetValueOrDefault("source")?.ToString() ?? "",
                        Metadata = ParseMetadata(hitDict.GetValueOrDefault("metadata"))
                    };
                    
                    results.Add(result);
                }
            }

            return results.OrderByDescending(r => r.Score).ToList();
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error searching OpenSearch: {ex.Message}");
            return new List<SearchResult>();
        }
    }

    public async Task<List<SearchResult>> VectorSearchAsync(float[] queryEmbedding, int maxResults = 5)
    {
        try
        {
            var searchResponse = await _client.SearchAsync<dynamic>(s => s
                .Index(_indexName)
                .Size(maxResults)
                .Query(q => q
                    .Knn(k => k
                        .Field("embedding")
                        .Vector(queryEmbedding)
                        .K(maxResults)
                    )
                )
                .Source(src => src
                    .Includes(i => i
                        .Field("text")
                        .Field("source")
                        .Field("metadata")
                        .Field("chunk_index")
                    )
                )
            );

            if (!searchResponse.IsValid)
            {
                Console.WriteLine($"Vector search failed: {searchResponse.OriginalException?.Message}");
                return new List<SearchResult>();
            }

            var results = new List<SearchResult>();
            
            foreach (var hit in searchResponse.Documents)
            {
                var hitDict = hit as IDictionary<string, object>;
                if (hitDict != null)
                {
                    var result = new SearchResult
                    {
                        Score = searchResponse.Hits.FirstOrDefault(h => h.Source.Equals(hit))?.Score ?? 0,
                        Text = hitDict.GetValueOrDefault("text")?.ToString() ?? "",
                        Source = hitDict.GetValueOrDefault("source")?.ToString() ?? "",
                        Metadata = ParseMetadata(hitDict.GetValueOrDefault("metadata"))
                    };
                    
                    results.Add(result);
                }
            }

            return results.OrderByDescending(r => r.Score).ToList();
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error in vector search: {ex.Message}");
            return new List<SearchResult>();
        }
    }

    private Dictionary<string, object> ParseMetadata(object? metadata)
    {
        if (metadata == null) return new Dictionary<string, object>();
        
        try
        {
            if (metadata is IDictionary<string, object> dict)
            {
                return dict.ToDictionary(kvp => kvp.Key, kvp => kvp.Value);
            }
            
            // If it's a JSON string, deserialize it
            if (metadata is string jsonString)
            {
                var parsed = JsonSerializer.Deserialize<Dictionary<string, object>>(jsonString);
                return parsed ?? new Dictionary<string, object>();
            }
            
            return new Dictionary<string, object>();
        }
        catch
        {
            return new Dictionary<string, object>();
        }
    }
}
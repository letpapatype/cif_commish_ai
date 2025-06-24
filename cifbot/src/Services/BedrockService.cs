using Amazon.BedrockRuntime;
using Amazon.BedrockRuntime.Model;
using QALambda.Models;
using System.Text.Json;

namespace QALambda.Services;

public class BedrockService
{
    private readonly AmazonBedrockRuntimeClient _bedrockClient;
    private readonly string _modelId = "anthropic.claude-3-sonnet-20240229-v1:0"; // Using Claude Sonnet

    public BedrockService(string region)
    {
        _bedrockClient = new AmazonBedrockRuntimeClient(Amazon.RegionEndpoint.GetBySystemName(region));
    }

    public async Task<BedrockAnswer> GenerateAnswerAsync(string question, List<SearchResult> searchResults)
    {
        try
        {
            // Build context from search results
            var context = BuildContext(searchResults);
            
            // Create the prompt
            var prompt = BuildPrompt(question, context);

            // Prepare the request for Claude
            var requestBody = new
            {
                anthropic_version = "bedrock-2023-05-31",
                max_tokens = 1000,
                messages = new[]
                {
                    new
                    {
                        role = "user",
                        content = prompt
                    }
                }
            };

            var request = new InvokeModelRequest
            {
                ModelId = _modelId,
                Body = new MemoryStream(JsonSerializer.SerializeToUtf8Bytes(requestBody)),
                ContentType = "application/json"
            };

            var response = await _bedrockClient.InvokeModelAsync(request);
            
            // Parse the response
            using var reader = new StreamReader(response.Body);
            var responseBody = await reader.ReadToEndAsync();
            var claudeResponse = JsonSerializer.Deserialize<ClaudeResponse>(responseBody);

            if (claudeResponse?.Content?.FirstOrDefault()?.Text != null)
            {
                return new BedrockAnswer
                {
                    Answer = claudeResponse.Content.First().Text,
                    Confidence = CalculateConfidence(searchResults)
                };
            }

            return new BedrockAnswer
            {
                Answer = "I couldn't generate a response based on the available information.",
                Confidence = 0.0
            };
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error calling Bedrock: {ex.Message}");
            return new BedrockAnswer
            {
                Answer = "I encountered an error while processing your question. Please try again.",
                Confidence = 0.0
            };
        }
    }

    private string BuildContext(List<SearchResult> searchResults)
    {
        var contextParts = new List<string>();
        
        for (int i = 0; i < searchResults.Count; i++)
        {
            var result = searchResults[i];
            var sourceInfo = GetSourceInfo(result.Source);
            
            contextParts.Add($"[Source {i + 1}: {sourceInfo}]\n{result.Text}\n");
        }

        return string.Join("\n---\n", contextParts);
    }

    private string GetSourceInfo(string source)
    {
        // Extract readable source information
        if (source.Contains("handbook") || source.Contains(".pdf"))
        {
            return source.Replace(".pdf", "").Replace("_", " ").Replace("-", " ");
        }
        return "Sports Handbook";
    }

    private string BuildPrompt(string question, string context)
    {
        return $@"You are an AI assistant helping with questions about high school sports organization handbooks. 

Based on the following information from the sports handbooks, please answer the user's question accurately and comprehensively.

CONTEXT FROM HANDBOOKS:
{context}

QUESTION: {question}

INSTRUCTIONS:
- Answer based ONLY on the information provided in the context above
- If the context doesn't contain enough information to answer the question, say so clearly
- Be specific and cite which handbook section your answer comes from when possible
- Keep your answer concise but complete
- If there are multiple relevant points, organize them clearly
- For rules or policies, be precise about the exact requirements

ANSWER:";
    }

    private double CalculateConfidence(List<SearchResult> searchResults)
    {
        if (!searchResults.Any()) return 0.0;

        // Simple confidence calculation based on search scores
        var avgScore = searchResults.Average(r => r.Score);
        var maxScore = searchResults.Max(r => r.Score);
        
        // Normalize to 0-1 range (this is a simple heuristic)
        var confidence = Math.Min(1.0, (avgScore + maxScore) / 2.0);
        
        // Boost confidence if we have multiple relevant results
        if (searchResults.Count >= 3 && avgScore > 0.5)
        {
            confidence = Math.Min(1.0, confidence * 1.2);
        }

        return Math.Round(confidence, 2);
    }

    // Helper classes for Claude response parsing
    private class ClaudeResponse
    {
        [JsonPropertyName("content")]
        public ClaudeContent[]? Content { get; set; }
    }

    private class ClaudeContent
    {
        [JsonPropertyName("text")]
        public string? Text { get; set; }
    }
}
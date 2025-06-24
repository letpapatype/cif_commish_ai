using System.Text.Json.Serialization;

namespace QALambda.Models;

public class QuestionRequest
{
    [JsonPropertyName("question")]
    public string Question { get; set; } = string.Empty;

    [JsonPropertyName("maxResults")]
    public int? MaxResults { get; set; } = 5;

    [JsonPropertyName("notificationEndpoint")]
    public string? NotificationEndpoint { get; set; }

    [JsonPropertyName("userId")]
    public string? UserId { get; set; }
}

public class QuestionResponse
{
    [JsonPropertyName("question")]
    public string Question { get; set; } = string.Empty;

    [JsonPropertyName("answer")]
    public string Answer { get; set; } = string.Empty;

    [JsonPropertyName("sources")]
    public List<string> Sources { get; set; } = new();

    [JsonPropertyName("confidence")]
    public double Confidence { get; set; }

    [JsonPropertyName("referencedChunks")]
    public int ReferencedChunks { get; set; }

    [JsonPropertyName("timestamp")]
    public DateTime Timestamp { get; set; } = DateTime.UtcNow;
}

public class SearchResult
{
    [JsonPropertyName("score")]
    public double Score { get; set; }

    [JsonPropertyName("text")]
    public string Text { get; set; } = string.Empty;

    [JsonPropertyName("source")]
    public string Source { get; set; } = string.Empty;

    [JsonPropertyName("metadata")]
    public Dictionary<string, object> Metadata { get; set; } = new();
}

public class BedrockAnswer
{
    public string Answer { get; set; } = string.Empty;
    public double Confidence { get; set; }
}
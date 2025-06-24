using Amazon.Lambda.Core;
using Amazon.Lambda.APIGatewayEvents;
using Amazon.SimpleNotificationService;
using Amazon.BedrockRuntime;
using System.Text.Json;
using QALambda.Services;
using QALambda.Models;

[assembly: LambdaSerializer(typeof(Amazon.Lambda.Serialization.SystemTextJson.DefaultLambdaJsonSerializer))]

namespace QALambda;

public class Function
{
    private readonly OpenSearchService _openSearchService;
    private readonly BedrockService _bedrockService;
    private readonly IAmazonSimpleNotificationService _snsClient;
    private readonly string _snsTopicArn;

    public Function()
    {
        var openSearchEndpoint = Environment.GetEnvironmentVariable("OPENSEARCH_ENDPOINT");
        var awsRegion = Environment.GetEnvironmentVariable("AWS_REGION");
        _snsTopicArn = Environment.GetEnvironmentVariable("SNS_TOPIC_ARN") ?? "";

        _openSearchService = new OpenSearchService(openSearchEndpoint!, awsRegion!);
        _bedrockService = new BedrockService(awsRegion!);
        _snsClient = new AmazonSimpleNotificationServiceClient();
    }

    public async Task<APIGatewayProxyResponse> FunctionHandler(
        APIGatewayProxyRequest request, 
        ILambdaContext context)
    {
        try
        {
            context.Logger.LogInformation($"Processing request: {request.Body}");

            // Parse the incoming request
            var questionRequest = JsonSerializer.Deserialize<QuestionRequest>(request.Body ?? "{}");
            
            if (string.IsNullOrWhiteSpace(questionRequest?.Question))
            {
                return new APIGatewayProxyResponse
                {
                    StatusCode = 400,
                    Body = JsonSerializer.Serialize(new { error = "Question is required" }),
                    Headers = new Dictionary<string, string> { { "Content-Type", "application/json" } }
                };
            }

            // Search for relevant documents
            var searchResults = await _openSearchService.SearchDocumentsAsync(
                questionRequest.Question, 
                questionRequest.MaxResults ?? 5);

            if (!searchResults.Any())
            {
                var noResultsResponse = new QuestionResponse
                {
                    Question = questionRequest.Question,
                    Answer = "I couldn't find any relevant information in the sports handbooks to answer your question.",
                    Sources = new List<string>(),
                    Confidence = 0.0
                };

                return await SendResponse(noResultsResponse, questionRequest.NotificationEndpoint);
            }

            // Generate answer using Bedrock
            var answer = await _bedrockService.GenerateAnswerAsync(
                questionRequest.Question, 
                searchResults);

            var response = new QuestionResponse
            {
                Question = questionRequest.Question,
                Answer = answer.Answer,
                Sources = searchResults.Select(r => r.Source).Distinct().ToList(),
                Confidence = answer.Confidence,
                ReferencedChunks = searchResults.Count
            };

            return await SendResponse(response, questionRequest.NotificationEndpoint);
        }
        catch (Exception ex)
        {
            context.Logger.LogError($"Error processing request: {ex.Message}");
            
            return new APIGatewayProxyResponse
            {
                StatusCode = 500,
                Body = JsonSerializer.Serialize(new { error = "Internal server error", details = ex.Message }),
                Headers = new Dictionary<string, string> { { "Content-Type", "application/json" } }
            };
        }
    }

    private async Task<APIGatewayProxyResponse> SendResponse(
        QuestionResponse response, 
        string? notificationEndpoint)
    {
        // Send SNS notification if endpoint provided
        if (!string.IsNullOrWhiteSpace(notificationEndpoint))
        {
            try
            {
                var snsMessage = new
                {
                    endpoint = notificationEndpoint,
                    response = response,
                    timestamp = DateTime.UtcNow
                };

                await _snsClient.PublishAsync(_snsTopicArn, JsonSerializer.Serialize(snsMessage));
            }
            catch (Exception ex)
            {
                // Log but don't fail the request
                Console.WriteLine($"Failed to send SNS notification: {ex.Message}");
            }
        }

        return new APIGatewayProxyResponse
        {
            StatusCode = 200,
            Body = JsonSerializer.Serialize(response),
            Headers = new Dictionary<string, string> 
            { 
                { "Content-Type", "application/json" },
                { "Access-Control-Allow-Origin", "*" },
                { "Access-Control-Allow-Headers", "Content-Type" },
                { "Access-Control-Allow-Methods", "POST, OPTIONS" }
            }
        };
    }
}
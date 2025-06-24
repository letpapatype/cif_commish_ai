import json
import boto3
import os
from typing import List, Dict
from pdf_processor import PDFProcessor
from opensearch_client import OpenSearchClient

# Initialize clients
s3_client = boto3.client('s3')
opensearch_client = OpenSearchClient(
    endpoint=os.environ['OPENSEARCH_ENDPOINT'],
    region=os.environ['AWS_REGION']
)
pdf_processor = PDFProcessor()

def lambda_handler(event, context):
    """
    Triggered when PDF is uploaded to S3
    Processes PDF and indexes into OpenSearch
    """
    try:
        # Parse S3 event
        for record in event['Records']:
            bucket = record['s3']['bucket']['name']
            key = record['s3']['object']['key']
            
            print(f"Processing {key} from bucket {bucket}")
            
            # Download PDF from S3
            response = s3_client.get_object(Bucket=bucket, Key=key)
            pdf_content = response['Body'].read()
            
            # Extract text and chunk it
            text_chunks = pdf_processor.process_pdf(pdf_content, key)
            
            # Generate embeddings and index to OpenSearch
            indexed_count = 0
            for chunk in text_chunks:
                opensearch_client.index_document(chunk)
                indexed_count += 1
            
            print(f"Successfully indexed {indexed_count} chunks from {key}")
            
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Successfully processed {len(event["Records"])} files',
                'chunks_indexed': indexed_count
            })
        }
        
    except Exception as e:
        print(f"Error processing PDF: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            })
        }
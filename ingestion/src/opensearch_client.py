import boto3
from opensearchpy import OpenSearch, RequestsHttpConnection
from aws_requests_auth.aws_auth import AWSRequestsAuth
import json
from typing import Dict, List

class OpenSearchClient:
    def __init__(self, endpoint: str, region: str):
        self.endpoint = endpoint
        self.region = region
        self.index_name = "sports-handbooks"
        
        # Set up AWS authentication
        credentials = boto3.Session().get_credentials()
        awsauth = AWSRequestsAuth(credentials, region, 'es')
        
        # Initialize OpenSearch client
        self.client = OpenSearch(
            hosts=[{'host': endpoint.replace('https://', ''), 'port': 443}],
            http_auth=awsauth,
            use_ssl=True,
            verify_certs=True,
            connection_class=RequestsHttpConnection
        )
        
        # Create index if it doesn't exist
        self._create_index_if_not_exists()
    
    def _create_index_if_not_exists(self):
        """Create the index with proper mapping for vector search"""
        if not self.client.indices.exists(index=self.index_name):
            index_mapping = {
                "mappings": {
                    "properties": {
                        "text": {
                            "type": "text",
                            "analyzer": "standard"
                        },
                        "embedding": {
                            "type": "knn_vector",
                            "dimension": 384,  # all-MiniLM-L6-v2 dimension
                            "method": {
                                "name": "hnsw",
                                "space_type": "cosinesimil",
                                "engine": "nmslib"
                            }
                        },
                        "source": {
                            "type": "keyword"
                        },
                        "chunk_index": {
                            "type": "integer"
                        },
                        "metadata": {
                            "type": "object",
                            "properties": {
                                "document_type": {"type": "keyword"},
                                "source_file": {"type": "keyword"},
                                "chunk_number": {"type": "integer"},
                                "total_chunks": {"type": "integer"}
                            }
                        }
                    }
                },
                "settings": {
                    "index": {
                        "knn": True,
                        "number_of_shards": 1,
                        "number_of_replicas": 0
                    }
                }
            }
            
            response = self.client.indices.create(
                index=self.index_name,
                body=index_mapping
            )
            print(f"Created index: {response}")
    
    def index_document(self, document: Dict):
        """Index a document chunk into OpenSearch"""
        try:
            response = self.client.index(
                index=self.index_name,
                id=document['id'],
                body=document
            )
            print(f"Indexed document {document['id']}: {response['result']}")
            return response
        except Exception as e:
            print(f"Error indexing document {document['id']}: {e}")
            raise
    
    def search_similar(self, query_embedding: List[float], size: int = 5) -> List[Dict]:
        """Search for similar documents using vector similarity"""
        search_body = {
            "size": size,
            "query": {
                "knn": {
                    "embedding": {
                        "vector": query_embedding,
                        "k": size
                    }
                }
            },
            "_source": ["text", "source", "metadata", "chunk_index"]
        }
        
        try:
            response = self.client.search(
                index=self.index_name,
                body=search_body
            )
            
            results = []
            for hit in response['hits']['hits']:
                results.append({
                    'score': hit['_score'],
                    'text': hit['_source']['text'],
                    'source': hit['_source']['source'],
                    'metadata': hit['_source']['metadata']
                })
            
            return results
        except Exception as e:
            print(f"Error searching documents: {e}")
            return []
    
    def hybrid_search(self, query_text: str, query_embedding: List[float], size: int = 5) -> List[Dict]:
        """Combine text search and vector search for better results"""
        search_body = {
            "size": size,
            "query": {
                "bool": {
                    "should": [
                        {
                            "match": {
                                "text": {
                                    "query": query_text,
                                    "boost": 1.0
                                }
                            }
                        },
                        {
                            "knn": {
                                "embedding": {
                                    "vector": query_embedding,
                                    "k": size,
                                    "boost": 2.0
                                }
                            }
                        }
                    ]
                }
            },
            "_source": ["text", "source", "metadata", "chunk_index"]
        }
        
        try:
            response = self.client.search(
                index=self.index_name,
                body=search_body
            )
            
            results = []
            for hit in response['hits']['hits']:
                results.append({
                    'score': hit['_score'],
                    'text': hit['_source']['text'],
                    'source': hit['_source']['source'],
                    'metadata': hit['_source']['metadata']
                })
            
            return results
        except Exception as e:
            print(f"Error in hybrid search: {e}")
            return []
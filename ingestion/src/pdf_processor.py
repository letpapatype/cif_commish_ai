import PyPDF2
import io
from typing import List, Dict
import hashlib
from sentence_transformers import SentenceTransformer
import re

class PDFProcessor:
    def __init__(self):
        # Initialize embedding model
        self.embedding_model = SentenceTransformer('all-MiniLM-L6-v2')
        
    def process_pdf(self, pdf_content: bytes, file_key: str) -> List[Dict]:
        """
        Extract text from PDF and return chunked documents with embeddings
        """
        # Extract text from PDF
        text = self._extract_text_from_pdf(pdf_content)
        
        # Clean and chunk the text
        chunks = self._chunk_text(text)
        
        # Create document objects with embeddings
        documents = []
        for i, chunk in enumerate(chunks):
            # Generate embedding
            embedding = self.embedding_model.encode(chunk).tolist()
            
            # Create document ID
            doc_id = self._generate_doc_id(file_key, i)
            
            document = {
                'id': doc_id,
                'text': chunk,
                'embedding': embedding,
                'source': file_key,
                'chunk_index': i,
                'metadata': {
                    'document_type': 'sports_handbook',
                    'source_file': file_key,
                    'chunk_number': i,
                    'total_chunks': len(chunks)
                }
            }
            documents.append(document)
            
        return documents
    
    def _extract_text_from_pdf(self, pdf_content: bytes) -> str:
        """Extract text from PDF bytes"""
        try:
            pdf_file = io.BytesIO(pdf_content)
            pdf_reader = PyPDF2.PdfReader(pdf_file)
            
            text = ""
            for page in pdf_reader.pages:
                text += page.extract_text() + "\n"
                
            return text
        except Exception as e:
            print(f"Error extracting text from PDF: {e}")
            return ""
    
    def _chunk_text(self, text: str, chunk_size: int = 1000, overlap: int = 200) -> List[str]:
        """
        Split text into overlapping chunks for better context preservation
        """
        # Clean text
        text = re.sub(r'\s+', ' ', text.strip())
        
        if len(text) <= chunk_size:
            return [text]
        
        chunks = []
        start = 0
        
        while start < len(text):
            end = start + chunk_size
            
            # Try to break at sentence boundary
            if end < len(text):
                # Look for sentence endings within the last 100 characters
                sentence_end = text.rfind('.', start, end)
                if sentence_end > start + chunk_size - 100:
                    end = sentence_end + 1
            
            chunk = text[start:end].strip()
            if chunk:
                chunks.append(chunk)
            
            # Move start position with overlap
            start = end - overlap
            if start >= len(text):
                break
                
        return chunks
    
    def _generate_doc_id(self, file_key: str, chunk_index: int) -> str:
        """Generate unique document ID"""
        content = f"{file_key}_{chunk_index}"
        return hashlib.md5(content.encode()).hexdigest()
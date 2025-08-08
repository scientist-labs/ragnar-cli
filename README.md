# Ruby RAG Pipeline

A pure Ruby implementation of a Retrieval-Augmented Generation (RAG) pipeline, demonstrating the integration of multiple Ruby NLP tools for document indexing, embedding, and retrieval.

## Features

- **Document Indexing**: Process text files and directories
- **Smart Chunking**: Uses the Baran gem for intelligent text chunking
- **Embeddings**: Generate embeddings using RedCandle (Ruby wrapper for Candle)
- **Vector Storage**: High-performance storage with Lance database via Lancelot gem
- **Dimensionality Reduction**: UMAP support through Annembed for efficient similarity search
- **CLI Interface**: User-friendly Thor-based command-line interface

## Installation

```bash
bundle install
```

## Usage

### Index Documents

Index a single file:
```bash
./bin/ruby-rag index path/to/document.txt
```

Index a directory of text files:
```bash
./bin/ruby-rag index path/to/documents/
```

Options:
- `--chunk-size`: Size of text chunks (default: 512)
- `--chunk-overlap`: Overlap between chunks (default: 50)
- `--model`: Embedding model to use (default: BAAI/bge-small-en-v1.5)
- `--db-path`: Path to Lance database (default: rag_database)

### Train UMAP Model

Train a UMAP model for dimensionality reduction:
```bash
./bin/ruby-rag train-umap
```

Options:
- `--n-components`: Target dimensions (default: 50)
- `--n-neighbors`: Number of neighbors for UMAP (default: 15)
- `--min-dist`: Minimum distance parameter (default: 0.1)
- `--model-path`: Path to save model (default: umap_model.bin)

### Apply UMAP Model

Apply the trained UMAP model to reduce embedding dimensions:
```bash
./bin/ruby-rag apply-umap
```

Options:
- `--model-path`: Path to UMAP model (default: umap_model.bin)
- `--batch-size`: Batch size for processing (default: 100)

### View Statistics

Check database statistics:
```bash
./bin/ruby-rag stats
```

## Architecture

### Components

1. **Chunker** (`lib/ruby_rag/chunker.rb`)
   - Uses Baran gem for intelligent text splitting
   - Maintains context with configurable overlap
   - Preserves document metadata

2. **Embedder** (`lib/ruby_rag/embedder.rb`)
   - Leverages RedCandle for embedding generation
   - Supports multiple embedding models
   - Batch processing with progress tracking

3. **Database** (`lib/ruby_rag/database.rb`)
   - Lance database integration via Lancelot
   - Efficient vector storage and retrieval
   - Support for both full and reduced embeddings

4. **Indexer** (`lib/ruby_rag/indexer.rb`)
   - Orchestrates the indexing pipeline
   - Handles file discovery and processing
   - Error recovery and progress reporting

5. **UMAP Processor** (`lib/ruby_rag/umap_processor.rb`)
   - Dimensionality reduction using Annembed
   - Model training and persistence
   - Batch application to existing embeddings

## Database Schema

The Lance database stores documents with the following structure:

- `id`: Unique identifier (UUID)
- `chunk_text`: The actual text content
- `file_path`: Source file path
- `chunk_index`: Position in the original document
- `embedding`: Full embedding vector
- `reduced_embedding`: UMAP-reduced embedding (optional)
- `metadata`: Additional metadata (JSON)

## Example Workflow

```bash
# 1. Index your documents
./bin/ruby-rag index ~/Documents/papers/

# 2. Check statistics
./bin/ruby-rag stats

# 3. Train UMAP for dimensionality reduction
./bin/ruby-rag train-umap --n-components 50

# 4. Apply UMAP to all embeddings
./bin/ruby-rag apply-umap

# 5. Check updated statistics
./bin/ruby-rag stats
```

## Dependencies

- **red-candle**: Ruby bindings for Candle (Rust ML framework)
- **lancelot**: Ruby bindings for Lance (columnar database)
- **annembed-ruby**: Ruby bindings for dimensionality reduction
- **baran**: Text chunking and splitting
- **thor**: CLI framework
- **tty-progressbar**: Progress visualization

## Future Enhancements

- Retrieval operations (similarity search, hybrid search)
- Query interface with reranking
- Support for multiple file formats (PDF, DOCX, etc.)
- Incremental indexing and updates
- Web interface for search and exploration
- Integration with LLMs for generation

## License

MIT
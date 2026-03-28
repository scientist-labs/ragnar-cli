<img src="/docs/assets/ragnar-wide.png" alt="ragnar" height="80px">

A complete Ruby implementation of Retrieval-Augmented Generation (RAG) pipeline using native Ruby ML/NLP gems.

## Overview

Ragnar provides a production-ready RAG pipeline for Ruby applications, integrating:
- **red-candle**: LLM inference, embeddings, and reranking
- **lancelot**: Vector database with Lance columnar storage
- **clusterkit**: UMAP dimensionality reduction and clustering
- **baran**: Text chunking and splitting

## Architecture

### Complete RAG Pipeline

```mermaid
graph TB
    subgraph "Indexing Pipeline"
        A[Documents] --> B[Chunker<br/>baran]
        B --> C[Embedder<br/>red-candle]
        C --> D[Vector DB<br/>lancelot]
        D --> E[UMAP Training<br/>annembed]
        E --> F[Reduced Embeddings]
    end

    subgraph "Query Pipeline"
        LLMCache[LLM Manager<br/>Cached Instance]
        Q[User Query] --> QR[Query Rewriter<br/>red-candle LLM]
        QR --> QE[Query Embedder<br/>red-candle]
        QE --> VS[Vector Search<br/>lancelot]
        VS --> RRF[RRF Fusion]
        RRF --> RR[Reranker<br/>red-candle]
        RR --> RP[Context Repacker<br/>Deduplication & Organization]
        RP --> LLM[Response Generation<br/>red-candle LLM]
        LLM --> R[Answer]

        LLMCache -.-> QR
        LLMCache -.-> LLM
    end

    D -.-> VS
    F -.-> VS
```

### Indexing Process

```mermaid
sequenceDiagram
    participant User
    participant CLI
    participant Indexer
    participant Chunker
    participant Embedder
    participant Database

    User->>CLI: ragnar index ./documents
    CLI->>Indexer: index_path(path)

    loop For each file
        Indexer->>Indexer: Read file
        Indexer->>Chunker: split_text(content)
        Chunker-->>Indexer: chunks[]

        loop For each chunk
            Indexer->>Embedder: embed(text)
            Embedder-->>Indexer: embedding[768]
            Indexer->>Database: add_document(chunk, embedding)
        end
    end

    Database-->>CLI: stats
    CLI-->>User: Indexed N documents
```

### UMAP Dimensionality Reduction

```mermaid
flowchart LR
    A[High-Dim Embeddings<br/>768D] --> B[UMAP Training]
    B --> C[Model]
    C --> D[Low-Dim Embeddings<br/>2-50D]

    B --> E[Parameters]
    E --> F[n_neighbors]
    E --> G[n_components]
    E --> H[min_dist]

    D --> I[Benefits]
    I --> J[Faster Search]
    I --> K[Less Memory]
    I --> L[Visualization]
```

### Query Processing Pipeline

```mermaid
flowchart TB
    Q[User Query] --> QA[Query Analysis<br/>w/ Cached LLM]

    QA --> CI[Clarified Intent]
    QA --> SQ[Sub-queries]
    QA --> KT[Key Terms]

    SQ --> EMB[Embed Each Query]
    EMB --> VS[Vector Search]

    VS --> RRF[RRF Fusion]
    RRF --> RANK[Reranking]

    RANK --> TOP[Top-K Documents]
    TOP --> CTX[Context Preparation]

    CTX --> REPACK[Context Repacking<br/>Deduplication<br/>Summarization<br/>Organization]

    REPACK --> GEN[LLM Generation<br/>w/ Same Cached LLM]
    CI --> GEN

    GEN --> ANS[Final Answer]
```

## Installation

### As a Gem

```bash
gem install ragnar-cli
```

### From Source

```bash
git clone https://github.com/scientist-labs/ragnar-cli.git
cd ragnar-cli
bundle install
gem build ragnar.gemspec
gem install ./ragnar-*.gem
```

## Quick Start

### 1. Index Documents

```bash
# Index a directory of text files
ragnar index ./documents

# Index with custom settings
ragnar index ./documents \
  --chunk-size 1000 \
  --chunk-overlap 100
```

### 2. Interactive Mode (TUI)

Running `ragnar` with no arguments launches an interactive TUI powered by [ratatui](https://ratatui.rs/):

```bash
# Launch the TUI (default when no command given)
ragnar

# Or explicitly
ragnar interactive
```

The TUI provides:
- **Auto-completion** for commands and options
- **Persistent history** across sessions
- **Live output** — see indexing progress, query results, and topic analysis inline
- **All CLI commands** available via `/command` syntax (e.g., `/index .`, `/umap train`, `/query "my question"`)
- **`/verbose`** — toggle verbose mode to see query pipeline details (retrieval, reranking, context)
- **`/profile`** — list or switch LLM profiles mid-session

### 3. Train UMAP (Optional)

Reduce embedding dimensions for faster search:

```bash
# Train UMAP model (auto-adjusts parameters based on data)
ragnar umap train \
  --n-components 50 \
  --n-neighbors 15

# Apply to all embeddings
ragnar umap apply
```

### 4. Extract Topics

Perform topic modeling to discover themes in your indexed documents:

```bash
# Basic topic extraction (requires minimum 20-30 indexed documents)
ragnar topics

# Adjust clustering parameters for smaller datasets
ragnar topics --min-cluster-size 3  # Allow smaller topics
ragnar topics --min-samples 2       # Less strict density requirements

# Export visualizations
ragnar topics --export html  # Interactive D3.js visualization
ragnar topics --export json  # JSON data for further processing

# Verbose mode for debugging
ragnar topics --verbose
```

**Note**: Topic modeling requires sufficient documents to identify meaningful patterns. For best results:
- Index at least 20-30 documents (ideally 50+)
- Ensure documents cover diverse topics
- Documents should be substantial (50+ words each)

The HTML export includes:
- **Topic Bubbles**: Interactive bubble chart showing topic sizes and coherence
- **Embedding Scatter Plot**: Visualization of all documents in embedding space, colored by cluster

### 5. Query the System

```bash
# Basic query
ragnar query "What is the main purpose of this project?"

# Verbose mode shows all intermediate processing steps
ragnar query "How does the chunking process work?" --verbose
# Or use short form
ragnar query "How does the chunking process work?" -v

# JSON output for programmatic use
ragnar query "Explain the embedding model" --json

# Adjust number of retrieved documents
ragnar query "What are the key features?" --top-k 5

# Combine options for detailed analysis
ragnar query "Compare Ruby with Python" -v --top-k 5
```

#### Verbose Mode Output

When using `--verbose` or `-v`, you'll see:
1. **Query Analysis**: Original query, clarified intent, sub-queries, and key terms
2. **Document Retrieval**: Each sub-query's embedding and search results
3. **RRF Fusion**: How multiple search results are combined
4. **Reranking**: Top documents after relevance scoring
5. **Context Repacking**: How retrieved chunks are organized and compressed
6. **Response Generation**: The final LLM prompt and response
7. **Final Results**: Confidence score and source attribution

### 6. Check Statistics

```bash
ragnar stats
```

## Features

### Intelligent Query Processing

1. **Query Rewriting**: Clarifies intent and generates sub-queries
2. **Multi-Query Search**: Searches with multiple query variations
3. **RRF Fusion**: Combines results using Reciprocal Rank Fusion
4. **Reranking**: Uses cross-encoder for precise relevance scoring
5. **Context Repacking**: Deduplicates and organizes retrieved chunks for optimal LLM consumption
6. **LLM Caching**: Single LLM instance shared between query rewriting and response generation
7. **Contextual Response**: Generates answers with LLM based on repacked context

### Embedding Management

- **High-dimensional embeddings** (768D) for semantic accuracy
- **UMAP reduction** to lower dimensions (2-50D) for efficiency
- **Automatic parameter adjustment** based on dataset size
- **Batch processing** for large document collections

### Database Features

- **Lance columnar format** for efficient storage
- **Vector similarity search** with configurable metrics
- **Metadata tracking** for source attribution
- **Incremental indexing** support

## Configuration

Ragnar uses a flexible YAML-based configuration system that allows you to customize all aspects of the RAG pipeline.

### Configuration File

Ragnar looks for configuration files in the following order:
1. `.ragnar.yml` in the current directory
2. `.ragnarrc.yml` in the current directory  
3. `ragnar.yml` in the current directory
4. `.ragnar.yml` in your home directory
5. Built-in defaults

Generate a configuration file:
```bash
# Create local config (in current directory)
ragnar init-config

# Create global config (in home directory)
ragnar init-config --global

# Force overwrite existing config
ragnar init-config --force
```

### Configuration Options

Example `.ragnar.yml` file:

```yaml
# Storage paths (all support ~ expansion)
storage:
  database_path: "~/.cache/ragnar/database"
  models_dir: "~/.cache/ragnar/models"
  history_file: "~/.cache/ragnar/history"

# Embedding configuration
embeddings:
  model: jinaai/jina-embeddings-v2-base-en
  chunk_size: 512
  chunk_overlap: 50

# UMAP dimensionality reduction
umap:
  reduced_dimensions: 64
  n_neighbors: 15
  min_dist: 0.1
  model_filename: umap_model.bin

# LLM profiles — switch between local and cloud models
llm:
  default_profile: red_candle
  profiles:
    red_candle:
      provider: red_candle
      model: MaziyarPanahi/Qwen3-4B-GGUF
    opus:
      provider: anthropic
      model: claude-opus-4-6
      api_key: sk-ant-...           # or set ANTHROPIC_API_KEY env var
    sonnet:
      provider: anthropic
      model: claude-sonnet-4-6
    ollama:
      provider: ollama
      model: llama3.1:8b

# Query processing
query:
  top_k: 3                          # Number of documents to retrieve
  enable_query_rewriting: true       # Use LLM to improve queries
  enable_reranking: true             # Cross-encoder reranking (disable for small corpora)
  reranker_model: BAAI/bge-reranker-base  # Reranker model

# Interactive mode
interactive:
  prompt: 'ragnar> '
  quiet_mode: true

# Output settings
output:
  show_progress: true
```

### LLM Profiles

Profiles let you switch between LLM providers without editing config. Use local models for development and cloud models for production quality:

```bash
# Use a specific profile for a single command
ragnar --profile opus query "What is our security policy?"

# In TUI mode, switch profiles mid-session
ragnar> /profile           # List available profiles
ragnar> /profile opus      # Switch to Opus
ragnar> /profile red_candle  # Switch back to local
```

Ragnar supports any [RubyLLM](https://rubyllm.com/) provider: `red_candle` (local), `anthropic`, `openai`, `ollama`, and more. API keys can be set per-profile in the config or via environment variables (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, etc.).

### Viewing Configuration

```bash
ragnar config     # Show all settings including active profile
ragnar model      # Show LLM model information
ragnar profile    # List all LLM profiles
```

In interactive mode (launch with `ragnar`):
```
ragnar> /config    # Show configuration
ragnar> /profile   # List profiles
```

### Environment Variables

Configuration values can be overridden with environment variables:
- `XDG_CACHE_HOME` - Override default cache directory (~/.cache)
- `ANTHROPIC_API_KEY` - Anthropic API key (used by anthropic profiles)
- `OPENAI_API_KEY` - OpenAI API key (used by openai profiles)

### Supported Models

**LLM Providers** (via RubyLLM):
- `red_candle` — Local GGUF models (default): `MaziyarPanahi/Qwen3-4B-GGUF`, `MaziyarPanahi/Qwen3-8B-GGUF`
- `anthropic` — Claude models: `claude-opus-4-6`, `claude-sonnet-4-6`
- `openai` — GPT models: `gpt-4o`, `gpt-4o-mini`
- `ollama` — Local Ollama models: `llama3.1:8b`, `mistral:7b`
- Any other [RubyLLM provider](https://rubyllm.com/providers/)

**Embedding Models** (via red-candle):
- `jinaai/jina-embeddings-v2-base-en` (default, 768 dimensions)
- `BAAI/bge-base-en-v1.5`
- `sentence-transformers/all-MiniLM-L6-v2`

**Reranker Models** (via red-candle, configurable):
- `BAAI/bge-reranker-base` (default, XLM-RoBERTa)
- `cross-encoder/ms-marco-MiniLM-L-12-v2` (smaller, BERT-based)

## Advanced Usage

### Programmatic API

```ruby
require 'ragnar'

# Initialize components
indexer = Ragnar::Indexer.new(
  db_path: "my_database",
  chunk_size: 1000
)

# Index documents
stats = indexer.index_path("./documents")

# Query the system
processor = Ragnar::QueryProcessor.new(db_path: "my_database")
result = processor.query(
  "What is Ruby?",
  top_k: 5,
  verbose: true
)

puts result[:answer]
puts "Confidence: #{result[:confidence]}%"
```

### Topic Modeling

Extract topics from your indexed documents:

```ruby
# Example with sufficient documents for clustering (minimum ~20-30 needed)
documents = [
  # Finance cluster
  "Federal Reserve raises interest rates to combat inflation",
  "Stock markets rally on positive earnings reports",
  "Cryptocurrency markets show increased volatility",
  "Corporate bonds yield higher returns this quarter",
  "Central banks coordinate global monetary policy",

  # Technology cluster
  "AI breakthrough in natural language processing announced",
  "Machine learning transforms healthcare diagnostics",
  "Cloud computing adoption accelerates in enterprises",
  "Quantum computing reaches new error correction milestone",
  "Open source frameworks receive major updates",

  # Healthcare cluster
  "Clinical trials show promise for cancer immunotherapy",
  "Telemedicine reshapes patient care delivery models",
  "Gene editing advances treatment for rare diseases",
  "Mental health awareness campaigns gain momentum",
  "mRNA vaccine technology platform expands",

  # Add more documents for better clustering...
  # See TOPIC_MODELING_EXAMPLE.md for complete example
]

# Extract topics using Topical
database = Ragnar::Database.new("ragnar_database")
docs = database.get_all_documents_with_embeddings

embeddings = docs.map { |d| d[:embedding] }
texts = docs.map { |d| d[:chunk_text] }

topics = Topical.extract(
  embeddings: embeddings,
  documents: texts,
  min_topic_size: 3  # Minimum docs per topic
)

topics.each do |topic|
  puts "Topic: #{topic.label}"
  puts "Terms: #{topic.terms.join(', ')}"
  puts "Size: #{topic.size} documents\n\n"
end
```

For a complete working example with 40+ documents, see [TOPIC_MODELING_EXAMPLE.md](TOPIC_MODELING_EXAMPLE.md).

### Custom Chunking Strategies

```ruby
chunker = Ragnar::Chunker.new(
  chunk_size: 1000,
  chunk_overlap: 200,
  separators: ["\n\n", "\n", ". ", " "]
)

chunks = chunker.chunk_text(document_text)
```

### Embedding Optimization

```ruby
# For small datasets (<100 documents)
processor = Ragnar::UmapProcessor.new
processor.train(
  n_components: 10,  # Fewer components
  n_neighbors: 5,    # Fewer neighbors
  min_dist: 0.05     # Tighter clusters
)

# For large datasets (>10,000 documents)
processor.train(
  n_components: 50,  # More components
  n_neighbors: 30,   # More neighbors
  min_dist: 0.1      # Standard distance
)
```

## Performance Considerations

### Memory Usage

- **Indexing**: ~100MB per 1000 documents (768D embeddings)
- **UMAP Training**: ~80MB for 10,000 vectors
- **Query Processing**: ~50MB overhead for models (reduced with LLM caching)
- **LLM Caching**: Single model instance (~500MB-2GB depending on model size)

### Speed Benchmarks

- **Indexing**: ~10 documents/second (including embedding)
- **UMAP Training**: 30-60 seconds for 10,000 vectors
- **Query Processing**: 1-3 seconds per query (faster with cached LLM)
- **Vector Search**: <100ms for 100,000 vectors
- **Context Repacking**: <50ms for typical document sets
- **LLM Loading**: 2-5 seconds (only on first query with caching)

### Optimization Tips

1. **Use UMAP** for datasets >1000 documents
2. **Batch index** large document collections
3. **Cache embeddings** for repeated queries
4. **Adjust chunk size** based on document type:
   - Technical docs: 500-1000 tokens
   - Narrative text: 200-500 tokens
   - Q&A content: 100-300 tokens

## Troubleshooting

### Common Issues

**UMAP fails with "index out of bounds"**
- Cause: Too few samples for the requested parameters
- Solution: System auto-adjusts, but you can manually set lower n_neighbors

**Slow indexing performance**
- Try smaller chunk sizes
- Use batch processing
- Consider using a faster embedding model

**Poor query results**
- Index more documents (RAG works best with 100+ documents)
- Adjust chunk size and overlap
- Try different embedding models

## Development

```bash
# Install dependencies
bundle install

# Run tests
bundle exec rspec

# Build gem
gem build ragnar.gemspec
```

## Architecture Details

### Component Responsibilities

| Component | Purpose | Key Methods |
|-----------|---------|-------------|
| Chunker | Split text into semantic chunks | `chunk_text()` |
| Embedder | Generate vector embeddings | `embed_text()`, `embed_batch()` |
| Database | Store and search vectors | `add_document()`, `search_similar()` |
| LLMManager | Cache and manage LLM instances | `get_llm()`, `default_llm()` |
| ContextRepacker | Optimize retrieved context | `repack()`, `repack_with_summary()` |
| QueryRewriter | Analyze and expand queries | `rewrite()` |
| QueryProcessor | Orchestrate query pipeline | `query()` |
| UmapProcessor | Reduce embedding dimensions | `train()`, `apply()` |

### Data Flow

1. **Documents** → Chunker → Text chunks
2. **Text chunks** → Embedder → Embeddings (768D)
3. **Embeddings** → Database → Stored vectors
4. **Stored vectors** → UMAP → Reduced vectors (2-50D)
5. **Query** → Rewriter (w/ cached LLM) → Sub-queries
6. **Sub-queries** → Embedder → Query vectors
7. **Query vectors** → Database → Similar documents
8. **Documents** → Reranker → Top results
9. **Top results** → Context Repacker → Optimized context
10. **Optimized context** → LLM (same cached instance) → Final answer

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

## License

MIT License - see LICENSE file for details

## Acknowledgments

This project integrates several excellent Ruby gems:
- [red-candle](https://github.com/assaydepot/red-candle) - Ruby ML/LLM toolkit
- [lancelot](https://github.com/scientist-labs/lancelot) - Lance database bindings
- [clusterkit](https://github.com/scientist-labs/clusterkit) - UMAP and clustering implementation
- [thor-interactive](https://github.com/scientist-labs/thor-interactive) - Interactive TUI for Thor CLIs
- [ratatui_ruby](https://github.com/nicholasgasior/ratatui-ruby) - Ratatui terminal UI bindings
- [parsekit](https://github.com/scientist-labs/parsekit) - Content extraction
- [baran](https://github.com/moeki0/baran) - Text splitting utilities

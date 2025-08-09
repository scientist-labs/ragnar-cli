require "thor"
require "red-candle"
require "lancelot"
require "annembed"
require "baran"
require "tty-progressbar"
require "securerandom"
require "json"
require "fileutils"

module RubyRag
  class Error < StandardError; end
  
  DEFAULT_DB_PATH = "rag_database"
  DEFAULT_CHUNK_SIZE = 512
  DEFAULT_CHUNK_OVERLAP = 50
  DEFAULT_EMBEDDING_MODEL = "jinaai/jina-embeddings-v2-base-en"
end

require_relative "ruby_rag/version"
require_relative "ruby_rag/database"
require_relative "ruby_rag/chunker"
require_relative "ruby_rag/embedder"
require_relative "ruby_rag/indexer"
require_relative "ruby_rag/umap_processor"
require_relative "ruby_rag/query_rewriter"
require_relative "ruby_rag/query_processor"
require_relative "ruby_rag/cli"
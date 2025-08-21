# frozen_string_literal: true

require "thor"
require "red-candle"
require "lancelot"
require "clusterkit"
require "baran"
require "tty-progressbar"
require "securerandom"
require "json"
require "fileutils"
require "singleton"

module Ragnar
  class Error < StandardError; end

  DEFAULT_DB_PATH = "ragnar_database"
  DEFAULT_CHUNK_SIZE = 512
  DEFAULT_CHUNK_OVERLAP = 50
  DEFAULT_EMBEDDING_MODEL = "jinaai/jina-embeddings-v2-base-en"
  DEFAULT_REDUCED_DIMENSIONS = 64  # Reduce embeddings from 768D to 64D for faster search
end

require_relative "ragnar/version"
require_relative "ragnar/database"
require_relative "ragnar/chunker"
require_relative "ragnar/embedder"
require_relative "ragnar/indexer"
require_relative "ragnar/umap_processor"
require_relative "ragnar/llm_manager"
require_relative "ragnar/context_repacker"
require_relative "ragnar/query_rewriter"
require_relative "ragnar/umap_transform_service"
require_relative "ragnar/query_processor"
require_relative "ragnar/topic_modeling"
require_relative "ragnar/cli"

# Keep backward compatibility
RubyRag = Ragnar
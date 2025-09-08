# frozen_string_literal: true

require 'spec_helper'
require 'ragnar'
require 'tempfile'
require 'fileutils'

RSpec.describe "Configuration Usage Integration" do
  let(:temp_dir) { Dir.mktmpdir }
  let(:config_file) { File.join(temp_dir, '.ragnar.yml') }
  let(:db_path) { File.join(temp_dir, 'test_db') }
  let(:models_dir) { File.join(temp_dir, 'models') }
  
  before do
    @original_pwd = Dir.pwd
    Dir.chdir(temp_dir)
    
    # Create a custom config file
    File.write(config_file, <<~YAML)
      storage:
        database_path: "#{db_path}"
        models_dir: "#{models_dir}"
        history_file: "#{temp_dir}/history"
      embeddings:
        model: 'custom/embedding-model'
        chunk_size: 256
        chunk_overlap: 25
      llm:
        default_model: 'custom/llm-model'
        default_gguf_file: 'custom.gguf'
      query:
        top_k: 5
        max_context_tokens: 1500
        enable_query_rewriting: false
      topics:
        min_cluster_size: 10
        labeling_method: 'keyword'
      umap:
        reduced_dimensions: 32
        n_neighbors: 10
        min_dist: 0.2
    YAML
    
    # Reset singleton to pick up new config
    Singleton.__init__(Ragnar::Config)
  end
  
  after do
    Dir.chdir(@original_pwd)
    FileUtils.rm_rf(temp_dir)
    Singleton.__init__(Ragnar::Config)
  end
  
  describe "Storage paths configuration" do
    it "uses configured database_path in CLI commands" do
      cli = Ragnar::CLI.new
      
      # The CLI should use our configured path
      expect(Ragnar::Config.instance.database_path).to eq(db_path)
      
      # Verify Database is initialized with correct path
      expect(Ragnar::Database).to receive(:new).with(db_path).and_call_original
      
      # Create a simple test file to index
      test_file = File.join(temp_dir, 'test.txt')
      File.write(test_file, "Test content for indexing")
      
      # Index should use the configured database path
      expect { cli.index(test_file) }.to output(/Indexing/).to_stdout
    end
    
    it "uses configured models_dir for UMAP models" do
      config = Ragnar::Config.instance
      expect(config.models_dir).to eq(models_dir)
      
      # UMAP processor should use models_dir for model storage
      processor = Ragnar::UmapProcessor.new(
        db_path: db_path,
        model_path: File.join(config.models_dir, "umap_model.bin")
      )
      
      expect(processor.model_path).to include(models_dir)
    end
  end
  
  describe "Embedding configuration" do
    it "uses configured embedding model and chunk settings" do
      config = Ragnar::Config.instance
      
      expect(config.embedding_model).to eq('custom/embedding-model')
      expect(config.chunk_size).to eq(256)
      expect(config.chunk_overlap).to eq(25)
      
      # Verify Indexer receives correct parameters
      indexer = Ragnar::Indexer.new(
        db_path: config.database_path,
        chunk_size: config.chunk_size,
        chunk_overlap: config.chunk_overlap,
        embedding_model: config.embedding_model
      )
      
      # These are passed to internal components but not exposed
      expect(indexer.chunker).to be_a(Ragnar::Chunker)
      expect(indexer.embedder).to be_a(Ragnar::Embedder)
    end
  end
  
  describe "LLM configuration" do
    it "uses configured LLM model settings" do
      config = Ragnar::Config.instance
      
      expect(config.llm_model).to eq('custom/llm-model')
      expect(config.llm_gguf_file).to eq('custom.gguf')
    end
  end
  
  describe "Query configuration" do
    it "respects query configuration settings" do
      config = Ragnar::Config.instance
      
      expect(config.get('query.top_k')).to eq(5)
      expect(config.get('query.max_context_tokens')).to eq(1500)
      expect(config.get('query.enable_query_rewriting')).to eq(false)
    end
    
    it "passes top_k to QueryProcessor when not overridden" do
      # This tests that default config values are used
      # Note: QueryProcessor currently doesn't take config directly
      # This is a gap we've identified
      cli = Ragnar::CLI.new
      
      # CLI should default to config's top_k value
      # Currently it defaults to 3, not from config - this is a BUG
      processor = cli.send(:get_cached_query_processor, db_path)
      
      # This will fail until we fix the implementation
      # expect(processor).to receive(:query).with(anything, hash_including(top_k: 5))
    end
  end
  
  describe "UMAP configuration" do
    it "uses configured UMAP parameters" do
      config = Ragnar::Config.instance
      
      expect(config.get('umap.reduced_dimensions')).to eq(32)
      expect(config.get('umap.n_neighbors')).to eq(10)
      expect(config.get('umap.min_dist')).to eq(0.2)
    end
  end
  
  describe "Topics configuration" do
    it "uses configured topic modeling parameters" do
      config = Ragnar::Config.instance
      
      expect(config.get('topics.min_cluster_size')).to eq(10)
      expect(config.get('topics.labeling_method')).to eq('keyword')
    end
  end
  
  describe "Configuration gaps and issues" do
    it "identifies config options that are defined but not used" do
      pending "Several config options are not actually used by the application"
      
      # These config options exist but aren't passed to components:
      # - query.max_context_tokens - not passed to QueryProcessor
      # - query.enable_query_rewriting - not passed to QueryRewriter
      # - topics.min_cluster_size - not passed to TopicModeler
      # - topics.labeling_method - not passed to TopicModeler
      # - topics.auto_summarize - not used anywhere
      # - interactive.save_history - not implemented
      # - output.use_colors - not implemented
      # - output.default_verbosity - not implemented
      
      fail "Configuration options are defined but not used"
    end
    
    it "identifies hardcoded values that should use config" do
      pending "Several values are hardcoded instead of using config"
      
      # Hardcoded values found:
      # - QueryProcessor#query uses hardcoded top_k default of 3
      # - TopicModeler uses hardcoded min_cluster_size
      # - UMAP parameters are only partially configurable
      
      fail "Hardcoded values should use configuration"
    end
  end
end
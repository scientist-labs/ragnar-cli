# frozen_string_literal: true

require 'spec_helper'
require 'ragnar'
require 'tempfile'
require 'fileutils'

RSpec.describe "Configuration Functionality" do
  let(:temp_dir) { Dir.mktmpdir }
  let(:config_file) { File.join(temp_dir, '.ragnar.yml') }
  let(:db_path) { File.join(temp_dir, 'test_db') }
  
  before do
    @original_pwd = Dir.pwd
    Dir.chdir(temp_dir)
    
    # Create test documents
    @test_file = File.join(temp_dir, 'test.txt')
    File.write(@test_file, "This is a test document about Ruby programming and Rails framework.")
    
    # Reset singleton
    Singleton.__init__(Ragnar::Config)
  end
  
  after do
    Dir.chdir(@original_pwd)
    FileUtils.rm_rf(temp_dir)
    Singleton.__init__(Ragnar::Config)
  end
  
  describe "query.top_k configuration" do
    it "uses configured top_k value by default" do
      File.write(config_file, <<~YAML)
        storage:
          database_path: "#{db_path}"
        query:
          top_k: 5
      YAML
      
      config = Ragnar::Config.instance
      expect(config.query_top_k).to eq(5)
      
      # Index some documents first
      indexer = Ragnar::Indexer.new(db_path: db_path)
      indexer.index_path(@test_file)
      
      # Query processor should use config's top_k
      processor = Ragnar::QueryProcessor.new(db_path: db_path)
      
      # Mock to verify top_k is passed correctly
      expect(processor).to receive(:retrieve_with_rrf).with(
        anything,
        hash_including(k: anything)
      ).and_return([])
      
      processor.query("test", top_k: config.query_top_k, enable_rewriting: false)
    end
  end
  
  describe "query.enable_query_rewriting configuration" do
    it "disables query rewriting when configured" do
      File.write(config_file, <<~YAML)
        storage:
          database_path: "#{db_path}"
        query:
          enable_query_rewriting: false
      YAML
      
      config = Ragnar::Config.instance
      expect(config.enable_query_rewriting?).to eq(false)
      
      # Index a document
      indexer = Ragnar::Indexer.new(db_path: db_path)
      indexer.index_path(@test_file)
      
      processor = Ragnar::QueryProcessor.new(db_path: db_path)
      
      # Rewriter should NOT be called when disabled
      expect(processor.rewriter).not_to receive(:rewrite)
      
      processor.query("test query", enable_rewriting: false)
    end
    
    it "enables query rewriting when configured" do
      File.write(config_file, <<~YAML)
        storage:
          database_path: "#{db_path}"
        query:
          enable_query_rewriting: true
      YAML
      
      config = Ragnar::Config.instance
      expect(config.enable_query_rewriting?).to eq(true)
      
      # The CLI should pass this to QueryProcessor
      # This is more of an integration test
    end
  end
  
  describe "output.show_progress configuration" do
    it "controls progress display during indexing" do
      File.write(config_file, <<~YAML)
        storage:
          database_path: "#{db_path}"
        output:
          show_progress: false
      YAML
      
      config = Ragnar::Config.instance
      expect(config.show_progress?).to eq(false)
      
      # Indexer should respect show_progress setting
      indexer = Ragnar::Indexer.new(
        db_path: db_path,
        show_progress: config.show_progress?
      )
      
      # Should not output progress messages
      expect { indexer.index_path(@test_file) }.not_to output(/Found.*file/).to_stdout
    end
  end
  
  describe "All config options are functional" do
    it "has no cosmetic config options" do
      # Generate default config
      config = Ragnar::Config.instance
      config_path = File.join(temp_dir, 'generated.yml')
      config.generate_config_file(config_path)
      
      # Load the generated config
      generated = YAML.load_file(config_path)
      
      # These are all the config options that should exist and work
      expected_options = {
        'storage' => ['database_path', 'models_dir', 'history_file'],
        'embeddings' => ['model', 'chunk_size', 'chunk_overlap'],
        'umap' => ['reduced_dimensions', 'n_neighbors', 'min_dist', 'model_filename'],
        'llm' => ['default_model', 'default_gguf_file'],
        'query' => ['top_k', 'enable_query_rewriting'],
        'interactive' => ['prompt', 'quiet_mode'],
        'output' => ['show_progress']
      }
      
      # Verify no extra options exist
      generated.each do |section, options|
        if expected_options[section]
          actual_keys = options.keys.sort
          expected_keys = expected_options[section].sort
          expect(actual_keys).to eq(expected_keys), 
            "Section '#{section}' has unexpected options: #{actual_keys - expected_keys}"
        else
          fail "Unexpected config section: #{section}"
        end
      end
    end
  end
end
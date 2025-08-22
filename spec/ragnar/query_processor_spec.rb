# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ragnar::QueryProcessor do
  let(:db_path) { File.join(@temp_dir, "test_db") }
  let(:processor) { described_class.new(db_path: db_path) }

  around(:each) do |example|
    Dir.mktmpdir do |temp_dir|
      @temp_dir = temp_dir
      
      # Set up a test database with some documents
      setup_test_database
      
      example.run
    end
  end
  
  before(:each) do
    # Stub LLMManager to prevent loading actual models
    llm_instance = instance_double(Ragnar::LLMManager)
    allow(Ragnar::LLMManager).to receive(:instance).and_return(llm_instance)
    
    # Mock the LLM
    mock_llm = double("LLM")
    allow(mock_llm).to receive(:generate).and_return("Test response")
    allow(mock_llm).to receive(:generate_with_schema).and_return({
      'clarified_intent' => 'test query',
      'query_type' => 'factual',
      'context_needed' => 'moderate',
      'sub_queries' => ['test query'],
      'key_terms' => []
    })
    allow(llm_instance).to receive(:default_llm).and_return(mock_llm)
    
    # Mock Candle EmbeddingModel to prevent loading
    mock_model = double("Candle::EmbeddingModel")
    @embedding_cache = {}
    allow(mock_model).to receive(:embedding) do |text|
      @embedding_cache[text] ||= Array.new(384) { rand }
      double("tensor", to_a: [@embedding_cache[text]])
    end
    allow(Candle::EmbeddingModel).to receive(:from_pretrained).and_return(mock_model)
  end

  def setup_test_database
    indexer = Ragnar::Indexer.new(db_path: db_path, show_progress: false)
    
    # Create test files with known content
    File.write(File.join(@temp_dir, "ruby.txt"), 
               "Ruby is a dynamic programming language. Ruby focuses on simplicity and productivity.")
    File.write(File.join(@temp_dir, "python.txt"), 
               "Python is a high-level programming language. Python emphasizes code readability.")
    File.write(File.join(@temp_dir, "javascript.txt"), 
               "JavaScript is a scripting language. JavaScript runs in browsers and Node.js.")
    
    suppress_stdout do
      indexer.index_path(@temp_dir)
    end
  end

  describe "#initialize" do
    it "creates a query processor" do
      expect(processor).to be_a(Ragnar::QueryProcessor)
    end

    it "initializes required components" do
      expect(processor.database).to be_a(Ragnar::Database)
      expect(processor.embedder).to be_a(Ragnar::Embedder)
      expect(processor.rewriter).to be_a(Ragnar::QueryRewriter)
    end
  end

  describe "#query" do
    it "processes a simple query" do
      result = processor.query("What is Ruby?", top_k: 2)
      
      expect(result).to be_a(Hash)
      expect(result).to have_key(:query)
      expect(result).to have_key(:answer)
    end

    it "accepts top_k parameter" do
      result = processor.query("test query", top_k: 1)
      
      expect(result).to be_a(Hash)
    end

    it "supports verbose mode" do
      output = capture_stdout do
        processor.query("test query", top_k: 1, verbose: true)
      end
      
      expect(output).to include("Processing query")
    end
  end

  # Test private methods indirectly through #query
  describe "RRF functionality (tested via #query)" do
    let(:database) { processor.database }
    
    it "uses RRF retrieval internally" do
      # Mock database responses to verify RRF is being used
      allow(database).to receive(:search_similar).and_return([
        { id: 1, distance: 0.1, chunk_text: "Ruby doc", file_path: "ruby.txt" },
        { id: 2, distance: 0.2, chunk_text: "Python doc", file_path: "python.txt" }
      ])
      
      result = processor.query("programming language", top_k: 2)
      
      expect(result).to be_a(Hash)
      expect(result[:sources]).to be_an(Array)
      expect(database).to have_received(:search_similar).at_least(:once)
    end
    
    it "handles multiple sub-queries through RRF" do
      # Mock rewriter to return multiple sub-queries
      allow_any_instance_of(Ragnar::QueryRewriter).to receive(:rewrite).and_return({
        'clarified_intent' => 'test query',
        'query_type' => 'factual',
        'context_needed' => 'moderate',
        'sub_queries' => ['query 1', 'query 2'],
        'key_terms' => []
      })
      
      result = processor.query("test", top_k: 2)
      
      expect(result).to be_a(Hash)
      expect(result[:sub_queries]).to eq(['query 1', 'query 2'])
    end
  end

  describe "performance" do
    it "processes queries in reasonable time" do
      start_time = Time.now
      processor.query("test query", top_k: 1)
      elapsed = Time.now - start_time
      
      # Should complete quickly for small dataset
      expect(elapsed).to be < 5.0
    end

    it "handles concurrent queries" do
      queries = ["Ruby", "Python", "JavaScript"]
      results = []
      threads = []
      
      queries.each do |query|
        threads << Thread.new do
          results << processor.query(query, top_k: 1)
        end
      end
      
      threads.each(&:join)
      
      expect(results.size).to eq(queries.size)
      results.each do |result|
        expect(result).to be_a(Hash)
      end
    end
  end
end
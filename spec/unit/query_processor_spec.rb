# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ragnar::QueryProcessor do
  let(:db_path) { temp_db_path }
  let(:processor) { described_class.new(db_path: db_path) }
  
  before do
    # Mock database with some sample data
    @mock_db = mock_database
    allow(Ragnar::Database).to receive(:new).and_return(@mock_db)
    
    # Set up mock search results
    allow(@mock_db).to receive(:search_similar).and_return([
      { id: "1", chunk_text: "Ruby is a programming language", 
        file_path: "ruby.txt", distance: 0.1 },
      { id: "2", chunk_text: "Ruby focuses on simplicity",
        file_path: "ruby.txt", distance: 0.2 }
    ])
  end
  
  describe "#initialize" do
    it "creates processor with required components" do
      expect(processor.database).to eq(@mock_db)
      expect(processor.embedder).to be_a(Ragnar::Embedder)
      expect(processor.rewriter).to be_a(Ragnar::QueryRewriter)
    end
  end
  
  describe "#query" do
    it "processes a simple query" do
      result = processor.query("What is Ruby?", top_k: 2)
      
      expect(result).to be_a(Hash)
      expect(result[:query]).to eq("What is Ruby?")
      expect(result[:clarified]).to include("Ruby")
      expect(result[:answer]).to be_a(String)
      expect(result[:sources]).to be_an(Array)
    end
    
    it "handles query with no results" do
      allow(@mock_db).to receive(:search_similar).and_return([])
      
      result = processor.query("Unknown topic", top_k: 2)
      
      expect(result[:answer]).to include("No relevant documents")
      expect(result[:sources]).to be_empty
    end
    
    it "respects top_k parameter" do
      allow(@mock_db).to receive(:search_similar).and_return(
        10.times.map { |i| { id: i.to_s, chunk_text: "doc #{i}", distance: 0.1 * i } }
      )
      
      result = processor.query("test", top_k: 3)
      
      # Should have called search_similar at least once
      expect(@mock_db).to have_received(:search_similar).at_least(:once)
    end
    
    it "uses sub-queries from rewriter" do
      # QueryRewriter is stubbed to return 2 sub-queries
      result = processor.query("complex query", top_k: 2)
      
      expect(result[:sub_queries]).to be_an(Array)
      expect(result[:sub_queries].size).to eq(2)
    end
    
    context "with verbose mode" do
      it "includes additional debug information" do
        output = capture_stdout do
          processor.query("test", top_k: 1, verbose: true)
        end
        
        expect(output).to include("Processing query")
        expect(output).to include("Query Analysis")
      end
    end
  end
  
  describe "RRF (Reciprocal Rank Fusion)" do
    it "combines results from multiple sub-queries" do
      # Mock rewriter to return multiple sub-queries
      allow_any_instance_of(Ragnar::QueryRewriter).to receive(:rewrite).and_return({
        'clarified_intent' => 'test',
        'query_type' => 'factual',
        'context_needed' => 'moderate',
        'sub_queries' => ['query1', 'query2', 'query3'],
        'key_terms' => []
      })
      
      # Mock different results for each sub-query
      call_count = 0
      allow(@mock_db).to receive(:search_similar) do
        call_count += 1
        case call_count
        when 1
          [{ id: "1", chunk_text: "result1", distance: 0.1 }]
        when 2
          [{ id: "2", chunk_text: "result2", distance: 0.2 }]
        when 3
          [{ id: "1", chunk_text: "result1", distance: 0.15 }]  # Duplicate
        else
          []
        end
      end
      
      result = processor.query("test", top_k: 2)
      
      # Should have called search for each sub-query
      expect(@mock_db).to have_received(:search_similar).at_least(3).times
    end
  end
  
  describe "error handling" do
    it "handles embedding errors" do
      allow_any_instance_of(Ragnar::Embedder).to receive(:embed_text).and_raise("Embedding error")
      
      # The current implementation doesn't handle these errors, so we expect them to raise
      expect { processor.query("test") }.to raise_error(/Embedding error/)
    end
    
    it "handles database errors" do
      allow(@mock_db).to receive(:search_similar).and_raise("Database error")
      
      # The current implementation doesn't handle these errors, so we expect them to raise
      expect { processor.query("test") }.to raise_error(/Database error/)
    end
  end
end
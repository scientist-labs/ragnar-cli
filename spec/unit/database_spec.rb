# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ragnar::Database do
  let(:db_path) { temp_db_path }
  let(:database) { described_class.new(db_path) }
  
  describe "#initialize" do
    it "creates database instance with path" do
      expect(database.db_path).to eq(db_path)
    end
  end
  
  describe "#add_documents" do
    it "handles empty documents array" do
      expect { database.add_documents([]) }.not_to raise_error
    end
    
    it "stores documents with required fields" do
      docs = sample_documents(2)
      
      # Mock Lancelot to avoid actual DB operations
      mock_dataset = double("Dataset")
      allow(Lancelot::Dataset).to receive(:open_or_create).and_return(mock_dataset)
      allow(mock_dataset).to receive(:add_documents)
      
      database.add_documents(docs)
      
      expect(Lancelot::Dataset).to have_received(:open_or_create)
      expect(mock_dataset).to have_received(:add_documents)
    end
    
    it "converts documents to Lance-compatible format" do
      docs = [
        {
          id: "test_1",
          chunk_text: "Test content",
          file_path: "test.txt",
          chunk_index: 0,
          embedding: [0.1, 0.2, 0.3],
          metadata: { source: "test" }
        }
      ]
      
      mock_dataset = double("Dataset")
      allow(Lancelot::Dataset).to receive(:open_or_create).and_return(mock_dataset)
      allow(mock_dataset).to receive(:add_documents)
      
      database.add_documents(docs)
      
      expect(mock_dataset).to have_received(:add_documents) do |converted_docs|
        doc = converted_docs.first
        expect(doc[:id]).to eq("test_1")
        expect(doc[:chunk_text]).to eq("Test content")
        expect(doc[:file_path]).to eq("test.txt")
        expect(doc[:chunk_index]).to eq(0)
        expect(doc[:embedding]).to eq([0.1, 0.2, 0.3])
        expect(doc[:metadata]).to eq('{"source":"test"}')  # JSON string
      end
    end
    
    it "creates proper schema based on embedding size" do
      docs = [
        {
          id: "test_1",
          chunk_text: "Test", 
          file_path: "test.txt",
          chunk_index: 0,
          embedding: [0.1, 0.2],  # 2 dimensions
          metadata: {}
        }
      ]
      
      mock_dataset = double("Dataset")
      allow(Lancelot::Dataset).to receive(:open_or_create).and_return(mock_dataset)
      allow(mock_dataset).to receive(:add_documents)
      
      database.add_documents(docs)
      
      expect(Lancelot::Dataset).to have_received(:open_or_create) do |path, options|
        schema = options[:schema]
        expect(schema[:embedding][:type]).to eq("vector")
        expect(schema[:embedding][:dimension]).to eq(2)
        expect(schema[:id]).to eq(:string)
        expect(schema[:chunk_text]).to eq(:string)
      end
    end
    
    it "clears dataset cache before and after modifications" do
      docs = sample_documents(1)
      
      mock_dataset = double("Dataset")
      allow(Lancelot::Dataset).to receive(:open_or_create).and_return(mock_dataset)
      allow(mock_dataset).to receive(:add_documents)
      allow(database).to receive(:clear_dataset_cache)
      
      database.add_documents(docs)
      
      expect(database).to have_received(:clear_dataset_cache).twice
    end
  end
  
  describe "#search_similar" do
    before do
      # Mock the dataset
      mock_dataset = double("Dataset")
      allow(Lancelot::Dataset).to receive(:open).and_return(mock_dataset)
      allow(mock_dataset).to receive(:vector_search).and_return([
        { id: "1", chunk_text: "result 1", file_path: "file1.txt", 
          chunk_index: 0, _distance: 0.1, metadata: "{}" },
        { id: "2", chunk_text: "result 2", file_path: "file2.txt",
          chunk_index: 0, _distance: 0.2, metadata: "{}" }
      ])
      allow(File).to receive(:exist?).with(db_path).and_return(true)
    end
    
    it "returns similar documents" do
      embedding = fake_embedding_for("query")
      results = database.search_similar(embedding, k: 2)
      
      expect(results.size).to eq(2)
      expect(results[0][:distance]).to eq(0.1)
      expect(results[1][:distance]).to eq(0.2)
    end
    
    it "returns empty array when dataset doesn't exist" do
      allow(File).to receive(:exist?).with(db_path).and_return(false)
      
      embedding = fake_embedding_for("query")
      results = database.search_similar(embedding)
      
      expect(results).to eq([])
    end
    
    it "accepts custom k parameter" do
      embedding = fake_embedding_for("query")
      results = database.search_similar(embedding, k: 5)
      
      expect(results.size).to eq(2)  # Mock returns 2, but k=5 requested
    end
    
    it "uses reduced embeddings when specified" do
      embedding = fake_embedding_for("query")
      
      # Mock the specific dataset instance
      mock_dataset = double("Dataset")
      allow(database).to receive(:cached_dataset).and_return(mock_dataset)
      allow(mock_dataset).to receive(:vector_search).with(
        embedding.to_a,
        column: :reduced_embedding,
        limit: 10
      ).and_return([])
      
      database.search_similar(embedding, k: 10, use_reduced: true)
      
      expect(mock_dataset).to have_received(:vector_search)
    end
    
    it "converts metadata from JSON strings" do
      embedding = fake_embedding_for("query")
      results = database.search_similar(embedding)
      
      expect(results[0][:metadata]).to eq({})  # Parsed from "{}"
      expect(results[1][:metadata]).to eq({})
    end
    
    it "returns properly formatted results" do
      embedding = fake_embedding_for("query")
      results = database.search_similar(embedding)
      
      result = results.first
      expect(result).to have_key(:id)
      expect(result).to have_key(:chunk_text)
      expect(result).to have_key(:file_path)
      expect(result).to have_key(:chunk_index)
      expect(result).to have_key(:distance)
      expect(result).to have_key(:metadata)
    end
  end
  
  describe "#get_embeddings" do
    let(:mock_docs) do
      [
        { id: "1", embedding: [0.1, 0.2], reduced_embedding: [0.1] },
        { id: "2", embedding: [0.3, 0.4], reduced_embedding: [0.2] },
        { id: "3", embedding: [0.5, 0.6], reduced_embedding: [0.3] }
      ]
    end
    
    before do
      allow(database).to receive(:dataset_exists?).and_return(true)
      allow(database).to receive(:cached_dataset).and_return(double("Dataset", to_a: mock_docs))
    end
    
    it "returns all embeddings without limit" do
      results = database.get_embeddings
      
      expect(results.size).to eq(3)
      expect(results[0][:id]).to eq("1")
      expect(results[0][:embedding]).to eq([0.1, 0.2])
      expect(results[0][:reduced_embedding]).to eq([0.1])
    end
    
    it "applies limit when specified" do
      mock_dataset = double("Dataset")
      allow(mock_dataset).to receive(:first).with(2).and_return(mock_docs.first(2))
      allow(database).to receive(:cached_dataset).and_return(mock_dataset)
      
      results = database.get_embeddings(limit: 2)
      
      expect(results.size).to eq(2)
      expect(results[0][:id]).to eq("1")
      expect(results[1][:id]).to eq("2")
    end
    
    it "applies offset and limit together" do
      mock_dataset = double("Dataset")
      allow(mock_dataset).to receive(:first).with(3).and_return(mock_docs) # limit + offset
      allow(database).to receive(:cached_dataset).and_return(mock_dataset)
      
      # Should get limit + offset, then drop offset
      allow(mock_docs).to receive(:drop).with(1).and_return(mock_docs[1..-1])
      
      results = database.get_embeddings(limit: 2, offset: 1)
      
      expect(results.size).to eq(2)
    end
    
    it "returns empty array when dataset doesn't exist" do
      allow(database).to receive(:dataset_exists?).and_return(false)
      
      results = database.get_embeddings
      
      expect(results).to eq([])
    end
  end
  
  describe "#update_reduced_embeddings" do
    let(:updates) do
      [
        { id: "1", reduced_embedding: [0.1, 0.2] },
        { id: "2", reduced_embedding: [0.3, 0.4] }
      ]
    end
    
    let(:existing_docs) do
      [
        { id: "1", chunk_text: "text1", embedding: [1, 2], metadata: "{}" },
        { id: "2", chunk_text: "text2", embedding: [3, 4], metadata: "{}" }
      ]
    end
    
    before do
      mock_dataset = double("Dataset")
      allow(mock_dataset).to receive(:to_a).and_return(existing_docs)
      allow(database).to receive(:cached_dataset).and_return(mock_dataset)
      allow(database).to receive(:clear_dataset_cache)
      allow(FileUtils).to receive(:rm_rf)
      
      # Mock the new dataset creation
      allow(Lancelot::Dataset).to receive(:open_or_create).and_return(double("NewDataset", add_documents: true))
    end
    
    it "handles empty updates array" do
      expect { database.update_reduced_embeddings([]) }.not_to raise_error
    end
    
    it "merges reduced embeddings with existing documents" do
      database.update_reduced_embeddings(updates)
      
      expect(Lancelot::Dataset).to have_received(:open_or_create) do |path, options|
        expect(options[:schema]).to have_key(:reduced_embedding)
        expect(options[:schema][:reduced_embedding][:type]).to eq("vector")
        expect(options[:schema][:reduced_embedding][:dimension]).to eq(2)
      end
    end
    
    it "recreates dataset with updated schema" do
      database.update_reduced_embeddings(updates)
      
      expect(FileUtils).to have_received(:rm_rf).with(db_path)
      expect(database).to have_received(:clear_dataset_cache).twice
    end
    
    it "preserves original document data" do
      new_dataset = double("NewDataset")
      allow(Lancelot::Dataset).to receive(:open_or_create).and_return(new_dataset)
      allow(new_dataset).to receive(:add_documents)
      
      database.update_reduced_embeddings(updates)
      
      expect(new_dataset).to have_received(:add_documents) do |docs|
        doc1 = docs.find { |d| d[:id] == "1" }
        expect(doc1[:chunk_text]).to eq("text1")
        expect(doc1[:embedding]).to eq([1, 2])
        expect(doc1[:reduced_embedding]).to eq([0.1, 0.2])
      end
    end
  end
  
  describe "#get_all_documents_with_embeddings" do
    before do
      allow(database).to receive(:dataset_exists?).and_return(true)
    end
    
    it "returns documents that have embeddings" do
      docs_with_embeddings = [
        { id: "1", embedding: [0.1, 0.2] },
        { id: "2", embedding: [0.3, 0.4] }
      ]
      
      mock_dataset = double("Dataset")
      allow(mock_dataset).to receive(:to_a).and_return(docs_with_embeddings)
      allow(database).to receive(:cached_dataset).and_return(mock_dataset)
      
      results = database.get_all_documents_with_embeddings
      
      expect(results.size).to eq(2)
      expect(results).to all(have_key(:embedding))
    end
    
    it "filters out documents without embeddings" do
      mixed_docs = [
        { id: "1", embedding: [0.1, 0.2] },
        { id: "2", embedding: nil },
        { id: "3", embedding: [] },
        { id: "4", embedding: [0.5, 0.6] }
      ]
      
      mock_dataset = double("Dataset")
      allow(mock_dataset).to receive(:to_a).and_return(mixed_docs)
      allow(database).to receive(:cached_dataset).and_return(mock_dataset)
      
      results = database.get_all_documents_with_embeddings
      
      expect(results.size).to eq(2)  # Only docs 1 and 4 have valid embeddings
      expect(results.map { |d| d[:id] }).to contain_exactly("1", "4")
    end
    
    it "applies limit when specified" do
      docs = Array.new(10) { |i| { id: "#{i}", embedding: [0.1, 0.2] } }
      
      mock_dataset = double("Dataset")
      allow(mock_dataset).to receive(:first).with(5).and_return(docs.first(5))
      allow(database).to receive(:cached_dataset).and_return(mock_dataset)
      
      results = database.get_all_documents_with_embeddings(limit: 5)
      
      expect(results.size).to eq(5)
    end
    
    it "returns empty array when dataset doesn't exist" do
      allow(database).to receive(:dataset_exists?).and_return(false)
      
      results = database.get_all_documents_with_embeddings
      
      expect(results).to eq([])
    end
  end
  
  describe "#count" do
    it "returns 0 when dataset doesn't exist" do
      allow(database).to receive(:dataset_exists?).and_return(false)
      expect(database.count).to eq(0)
    end
    
    it "returns document count" do
      mock_dataset = double("Dataset")
      allow(database).to receive(:dataset_exists?).and_return(true)
      allow(database).to receive(:cached_dataset).and_return(mock_dataset)
      allow(mock_dataset).to receive(:to_a).and_return([{}, {}, {}])
      
      expect(database.count).to eq(3)
    end
  end
  
  describe "#get_stats" do
    it "returns empty stats when dataset doesn't exist" do
      allow(database).to receive(:dataset_exists?).and_return(false)
      
      stats = database.get_stats
      expect(stats[:document_count]).to eq(0)
      expect(stats[:total_documents]).to eq(0)
      expect(stats[:unique_files]).to eq(0)
    end
    
    it "calculates statistics from documents" do
      docs = [
        { id: "1", chunk_text: "text1" * 10, file_path: "f1.txt", 
          embedding: [0.1, 0.2], reduced_embedding: nil },
        { id: "2", chunk_text: "text2" * 10, file_path: "f1.txt",
          embedding: [0.3, 0.4], reduced_embedding: nil },
        { id: "3", chunk_text: "text3" * 10, file_path: "f2.txt",
          embedding: [0.5, 0.6], reduced_embedding: nil }
      ]
      
      mock_dataset = double("Dataset")
      allow(database).to receive(:dataset_exists?).and_return(true)
      allow(database).to receive(:cached_dataset).and_return(mock_dataset)
      allow(mock_dataset).to receive(:to_a).and_return(docs)
      
      stats = database.get_stats
      
      expect(stats[:total_documents]).to eq(3)
      expect(stats[:unique_files]).to eq(2)
      expect(stats[:with_embeddings]).to eq(3)
      expect(stats[:embedding_dims]).to eq(2)
    end
  end
  
  describe "#full_text_search" do
    it "performs text search" do
      mock_dataset = double("Dataset")
      allow(database).to receive(:dataset_exists?).and_return(true)
      allow(database).to receive(:cached_dataset).and_return(mock_dataset)
      allow(mock_dataset).to receive(:full_text_search).and_return([
        { id: "1", chunk_text: "matching text", file_path: "file.txt",
          chunk_index: 0, metadata: "{}" }
      ])
      
      results = database.full_text_search("query", limit: 5)
      
      expect(results.size).to eq(1)
      expect(results[0][:chunk_text]).to eq("matching text")
    end
    
    it "returns empty array when dataset doesn't exist" do
      allow(database).to receive(:dataset_exists?).and_return(false)
      
      results = database.full_text_search("query")
      expect(results).to eq([])
    end
  end
end
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
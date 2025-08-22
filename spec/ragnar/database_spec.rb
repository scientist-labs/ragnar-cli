# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ragnar::Database do
  let(:db_path) { File.join(@temp_dir, "test_database") }
  let(:database) { described_class.new(db_path) }

  around(:each) do |example|
    Dir.mktmpdir do |temp_dir|
      @temp_dir = temp_dir
      example.run
    end
  end

  describe "#initialize" do
    it "creates a new database instance" do
      expect(database).to be_a(Ragnar::Database)
    end

    it "sets the database path" do
      expect(database.db_path).to eq(db_path)
    end

    it "sets the default table name" do
      expect(database.table_name).to eq("documents")
    end

    it "accepts a custom table name" do
      custom_db = described_class.new(db_path, table_name: "custom_docs")
      expect(custom_db.table_name).to eq("custom_docs")
    end
  end

  describe "#add_documents" do
    let(:documents) do
      [
        {
          id: "doc1",
          chunk_text: "This is a test document",
          file_path: "/path/to/file.txt",
          chunk_index: 0,
          embedding: Array.new(768, 0.1),
          metadata: { key: "value" }
        },
        {
          id: "doc2",
          chunk_text: "Another test document",
          file_path: "/path/to/file2.txt",
          chunk_index: 1,
          embedding: Array.new(768, 0.2),
          metadata: { key: "value2" }
        }
      ]
    end

    it "adds documents to the database" do
      expect { database.add_documents(documents) }.not_to raise_error
    end

    it "handles empty document array" do
      expect { database.add_documents([]) }.not_to raise_error
    end
  end

  describe "#get_embeddings" do
    let(:documents) do
      [
        {
          id: "doc1",
          chunk_text: "Test document 1",
          file_path: "/path/to/file1.txt",
          chunk_index: 0,
          embedding: Array.new(768, 0.1),
          metadata: { key: "value1" }
        },
        {
          id: "doc2",
          chunk_text: "Test document 2",
          file_path: "/path/to/file2.txt",
          chunk_index: 1,
          embedding: Array.new(768, 0.2),
          metadata: { key: "value2" }
        }
      ]
    end

    before do
      database.add_documents(documents)
    end

    it "retrieves all embeddings when no limit is specified" do
      embeddings = database.get_embeddings
      expect(embeddings).to be_an(Array)
      expect(embeddings.size).to eq(2)
    end

    it "respects the limit parameter" do
      embeddings = database.get_embeddings(limit: 1)
      expect(embeddings.size).to eq(1)
    end

    it "respects the offset parameter" do
      all_embeddings = database.get_embeddings
      if all_embeddings.size >= 2
        embeddings = database.get_embeddings(limit: 1, offset: 1)
        expect(embeddings.size).to eq(1)
        # Should get the second document
        expect(embeddings.first[:id]).not_to eq(all_embeddings.first[:id])
      else
        skip "Not enough documents to test offset"
      end
    end

    it "returns empty array when database doesn't exist" do
      empty_db = described_class.new(File.join(@temp_dir, "nonexistent"))
      expect(empty_db.get_embeddings).to eq([])
    end
  end

  describe "#search_similar" do
    let(:documents) do
      [
        {
          id: "doc1",
          chunk_text: "Ruby programming language",
          file_path: "/path/to/ruby.txt",
          chunk_index: 0,
          embedding: Array.new(768) { rand },
          metadata: { language: "ruby" }
        },
        {
          id: "doc2",
          chunk_text: "Python programming language",
          file_path: "/path/to/python.txt",
          chunk_index: 0,
          embedding: Array.new(768) { rand },
          metadata: { language: "python" }
        }
      ]
    end

    before do
      database.add_documents(documents)
    end

    it "searches for similar documents" do
      query_embedding = Array.new(768) { rand }
      results = database.search_similar(query_embedding, k: 1)
      
      expect(results).to be_an(Array)
      expect(results.size).to be <= 1
    end

    it "returns empty array when database doesn't exist" do
      empty_db = described_class.new(File.join(@temp_dir, "nonexistent"))
      query_embedding = Array.new(768) { rand }
      expect(empty_db.search_similar(query_embedding)).to eq([])
    end

    it "respects the k parameter" do
      query_embedding = Array.new(768) { rand }
      results = database.search_similar(query_embedding, k: 2)
      
      expect(results.size).to be <= 2
    end
  end

  describe "#get_stats" do
    it "returns stats for empty database" do
      stats = database.get_stats
      expect(stats).to be_a(Hash)
      expect(stats[:document_count]).to eq(0)
    end

    it "returns correct stats after adding documents" do
      documents = [
        {
          id: "doc1",
          chunk_text: "Test",
          file_path: "/test.txt",
          chunk_index: 0,
          embedding: Array.new(768, 0.1),
          metadata: {}
        }
      ]
      
      database.add_documents(documents)
      stats = database.get_stats
      expect(stats).to be_a(Hash)
      # Stats should have some expected keys
      expect(stats).to have_key(:document_count)
      expect(stats[:document_count]).to be > 0
    end
  end

  describe "#dataset_exists?" do
    it "returns false for non-existent database" do
      expect(database.dataset_exists?).to be false
    end

    it "returns true after adding documents" do
      documents = [
        {
          id: "doc1",
          chunk_text: "Test",
          file_path: "/test.txt",
          chunk_index: 0,
          embedding: Array.new(768, 0.1),
          metadata: {}
        }
      ]
      
      database.add_documents(documents)
      expect(database.dataset_exists?).to be true
    end
  end
end
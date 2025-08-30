# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ragnar::Indexer do
  let(:db_path) { temp_db_path }
  let(:indexer) { described_class.new(db_path: db_path, show_progress: false) }
  
  before do
    # Mock the database to avoid actual DB operations
    @mock_db = mock_database
    allow(Ragnar::Database).to receive(:new).and_return(@mock_db)
  end
  
  describe "#initialize" do
    it "creates indexer with configuration" do
      expect(indexer.database).to eq(@mock_db)
      expect(indexer.chunker).to be_a(Ragnar::Chunker)
      expect(indexer.embedder).to be_a(Ragnar::Embedder)
    end
    
    it "accepts custom chunk parameters" do
      custom = described_class.new(
        db_path: db_path,
        chunk_size: 1000,
        chunk_overlap: 100,
        show_progress: false
      )
      
      expect(custom.chunker.chunk_size).to eq(1000)
      expect(custom.chunker.chunk_overlap).to eq(100)
    end
  end
  
  describe "#index_path" do
    context "with single file" do
      it "indexes a text file" do
        file = temp_file("test.txt", "This is test content for indexing.")
        
        stats = suppress_output { indexer.index_path(file) }
        
        expect(stats[:files_processed]).to eq(1)
        expect(stats[:chunks_created]).to be > 0
        expect(stats[:errors]).to eq(0)
      end
      
      it "handles non-existent file" do
        stats = suppress_output { indexer.index_path("/non/existent/file.txt") }
        
        expect(stats[:files_processed]).to eq(0)
        expect(stats[:chunks_created]).to eq(0)
      end
    end
    
    context "with directory" do
      it "indexes all text files in directory" do
        create_sample_files  # Creates 3 files in temp_dir
        
        stats = suppress_output { indexer.index_path(temp_dir) }
        
        expect(stats[:files_processed]).to eq(3)
        expect(stats[:chunks_created]).to be > 0
        expect(stats[:errors]).to eq(0)
      end
      
      it "handles empty directory" do
        empty_dir = Dir.mktmpdir
        
        stats = suppress_output { indexer.index_path(empty_dir) }
        
        expect(stats[:files_processed]).to eq(0)
        expect(stats[:chunks_created]).to eq(0)
        
        FileUtils.rm_rf(empty_dir)
      end
      
      it "skips non-text files" do
        temp_file("text.txt", "text content")
        temp_file("image.jpg", "\xFF\xD8\xFF")  # JPEG header
        
        stats = suppress_output { indexer.index_path(temp_dir) }
        
        expect(stats[:files_processed]).to eq(1)  # Only the text file
      end
    end
    
    context "error handling" do
      it "counts errors for problematic files" do
        file = temp_file("bad.txt", "content")
        
        # Make embedder raise an error
        allow_any_instance_of(Ragnar::Embedder).to receive(:embed_batch).and_raise("Embedding error")
        
        stats = suppress_output { indexer.index_path(file) }
        
        expect(stats[:files_processed]).to eq(0)
        expect(stats[:errors]).to eq(1)
      end
    end
  end
  
  describe "#index_text" do
    it "indexes raw text directly" do
      text = "This is some text to index directly without reading from a file."
      metadata = { source: "direct", timestamp: Time.now.to_s }
      
      stats = indexer.index_text(text, metadata)
      
      expect(stats).to be > 0  # Returns number of chunks created
    end
    
    it "handles empty text" do
      stats = indexer.index_text("", {})
      expect(stats).to eq(0)
    end
  end
  
  describe "#index_files" do
    it "indexes multiple specific files" do
      files = create_sample_files.take(2)  # Just 2 files
      
      stats = indexer.index_files(files)
      
      expect(stats[:files_processed]).to eq(2)
      expect(stats[:chunks_created]).to be > 0
    end
    
    it "skips non-existent files" do
      files = ["/fake/file1.txt", "/fake/file2.txt"]
      
      stats = indexer.index_files(files)
      
      expect(stats[:files_processed]).to eq(0)
      expect(stats[:chunks_created]).to eq(0)
    end
  end
  
  describe "#index_directory" do
    it "delegates to index_path" do
      allow(indexer).to receive(:index_path).and_return({ files_processed: 1 })
      
      result = indexer.index_directory("/some/dir")
      
      expect(indexer).to have_received(:index_path).with("/some/dir")
      expect(result[:files_processed]).to eq(1)
    end
  end
end
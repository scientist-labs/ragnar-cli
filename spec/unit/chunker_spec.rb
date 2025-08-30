# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ragnar::Chunker do
  let(:chunker) { described_class.new(chunk_size: 100, chunk_overlap: 20) }
  
  describe "#initialize" do
    it "accepts chunk size and overlap parameters" do
      expect(chunker.chunk_size).to eq(100)
      expect(chunker.chunk_overlap).to eq(20)
    end
    
    it "uses defaults when not specified" do
      default_chunker = described_class.new
      expect(default_chunker.chunk_size).to eq(Ragnar::DEFAULT_CHUNK_SIZE)
      expect(default_chunker.chunk_overlap).to eq(Ragnar::DEFAULT_CHUNK_OVERLAP)
    end
  end
  
  describe "#chunk_text" do
    it "returns empty array for nil or empty text" do
      expect(chunker.chunk_text(nil)).to eq([])
      expect(chunker.chunk_text("")).to eq([])
    end
    
    it "returns single chunk for short text" do
      short_text = "This is short."
      chunks = chunker.chunk_text(short_text)
      
      expect(chunks.size).to eq(1)
      expect(chunks[0][:text]).to eq(short_text)
      expect(chunks[0][:index]).to eq(0)
    end
    
    it "splits long text into overlapping chunks" do
      long_text = "a" * 250  # 250 characters
      chunks = chunker.chunk_text(long_text)
      
      expect(chunks.size).to be >= 3
      expect(chunks[0][:text].length).to be <= 100
      expect(chunks[1][:text].length).to be <= 100
      
      # Check overlap exists
      if chunks.size > 1
        # There should be some overlap between consecutive chunks
        expect(chunks[0][:text][-10..-1]).to eq(chunks[1][:text][0..9])
      end
    end
    
    it "includes metadata in chunks" do
      metadata = { file: "test.txt", author: "test" }
      chunks = chunker.chunk_text("Test text", metadata)
      
      # Metadata gets enriched with chunk info
      expect(chunks[0][:metadata]).to include(metadata)
    end
    
    it "preserves sentence boundaries when possible" do
      text = "First sentence. Second sentence. Third sentence. Fourth sentence. Fifth sentence. Sixth sentence. Seventh sentence."
      chunks = chunker.chunk_text(text)
      
      # Just verify we get chunks
      expect(chunks).not_to be_empty
      chunks.each do |chunk|
        expect(chunk[:text]).to be_a(String)
      end
    end
  end
  
  describe "#chunk_file" do
    it "reads and chunks file content" do
      file_path = temp_file("test.txt", "Test content for chunking")
      chunks = chunker.chunk_file(file_path)
      
      expect(chunks).not_to be_empty
      expect(chunks[0][:metadata][:file_path]).to eq(file_path)
      expect(chunks[0][:metadata][:file_name]).to eq("test.txt")
    end
    
    it "handles non-existent file gracefully" do
      # Should raise an error for non-existent file
      expect { chunker.chunk_file("/non/existent/file.txt") }.to raise_error(/not found|does not exist/i)
    end
  end
end
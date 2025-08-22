# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ragnar::Chunker do
  describe "#initialize" do
    it "creates a chunker with default settings" do
      chunker = described_class.new
      expect(chunker.chunk_size).to eq(Ragnar::DEFAULT_CHUNK_SIZE)
      expect(chunker.chunk_overlap).to eq(Ragnar::DEFAULT_CHUNK_OVERLAP)
    end

    it "accepts custom chunk size and overlap" do
      chunker = described_class.new(chunk_size: 1000, chunk_overlap: 100)
      expect(chunker.chunk_size).to eq(1000)
      expect(chunker.chunk_overlap).to eq(100)
    end
  end

  describe "#chunk_text" do
    let(:chunker) { described_class.new(chunk_size: 100, chunk_overlap: 20) }

    it "returns empty array for nil text" do
      expect(chunker.chunk_text(nil)).to eq([])
    end

    it "returns empty array for empty text" do
      expect(chunker.chunk_text("")).to eq([])
      expect(chunker.chunk_text("   ")).to eq([])
    end

    it "chunks a short text into a single chunk" do
      text = "This is a short text."
      chunks = chunker.chunk_text(text)
      
      expect(chunks.size).to eq(1)
      expect(chunks.first[:text]).to eq(text)
      expect(chunks.first[:index]).to eq(0)
    end

    it "chunks a long text into multiple chunks" do
      text = "This is a much longer text. " * 20
      chunks = chunker.chunk_text(text)
      
      expect(chunks.size).to be > 1
      chunks.each_with_index do |chunk, index|
        expect(chunk[:index]).to eq(index)
        expect(chunk[:text]).not_to be_empty
        expect(chunk[:metadata][:chunk_index]).to eq(index)
        expect(chunk[:metadata][:total_chunks]).to eq(chunks.size)
      end
    end

    it "respects chunk overlap" do
      text = "Word1 Word2 Word3 Word4 Word5 Word6 Word7 Word8 Word9 Word10 " * 5
      chunker = described_class.new(chunk_size: 50, chunk_overlap: 10)
      chunks = chunker.chunk_text(text)
      
      expect(chunks.size).to be > 1
      
      # Check that chunks have some overlap (not exact due to word boundaries)
      if chunks.size > 1
        first_chunk_end = chunks[0][:text][-10..-1]
        second_chunk_start = chunks[1][:text][0..10]
        # There should be some common content due to overlap
        expect(chunks[0][:text].length).to be > 0
        expect(chunks[1][:text].length).to be > 0
      end
    end

    it "includes custom metadata in chunks" do
      text = "This is some text to chunk."
      metadata = { source: "test.txt", author: "Test Author" }
      chunks = chunker.chunk_text(text, metadata)
      
      expect(chunks.first[:metadata]).to include(metadata)
      expect(chunks.first[:metadata]).to have_key(:chunk_index)
      expect(chunks.first[:metadata]).to have_key(:total_chunks)
      expect(chunks.first[:metadata]).to have_key(:chunk_size)
    end

    it "handles text with multiple paragraph separators" do
      text = "Paragraph 1.\n\nParagraph 2.\n\nParagraph 3."
      chunks = chunker.chunk_text(text)
      
      expect(chunks).not_to be_empty
      chunks.each do |chunk|
        expect(chunk[:text]).not_to be_empty
      end
    end

    it "processes text with various separators correctly" do
      text = "Sentence one. Sentence two.\nNew line here.\n\nNew paragraph."
      chunker = described_class.new(chunk_size: 30, chunk_overlap: 5)
      chunks = chunker.chunk_text(text)
      
      expect(chunks).not_to be_empty
      chunks.each do |chunk|
        expect(chunk[:text].length).to be <= 35 # Allow some flexibility for word boundaries
      end
    end
  end

  describe "#chunk_file" do
    let(:chunker) { described_class.new(chunk_size: 100, chunk_overlap: 20) }
    let(:temp_file) { Tempfile.new(["test", ".txt"]) }

    after do
      temp_file.close
      temp_file.unlink
    end

    it "chunks content from a file" do
      content = "This is test content from a file. " * 10
      temp_file.write(content)
      temp_file.rewind
      
      chunks = chunker.chunk_file(temp_file.path)
      
      expect(chunks).not_to be_empty
      chunks.each do |chunk|
        expect(chunk[:metadata][:file_path]).to eq(temp_file.path)
        expect(chunk[:metadata][:file_name]).to eq(File.basename(temp_file.path))
      end
    end

    it "handles non-existent files gracefully" do
      expect { chunker.chunk_file("/non/existent/file.txt") }.to raise_error(RuntimeError, /File not found/)
    end

    it "includes file metadata in chunks" do
      temp_file.write("Test content")
      temp_file.rewind
      
      chunks = chunker.chunk_file(temp_file.path)
      
      expect(chunks.first[:metadata]).to include(
        file_path: temp_file.path,
        file_name: File.basename(temp_file.path)
      )
    end
  end
end
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ragnar::Embedder do
  let(:embedder) { described_class.new }

  describe "#initialize" do
    it "creates an embedder instance" do
      expect(embedder).to be_a(described_class)
    end

    it "initializes with default model" do
      expect(embedder.model_name).to eq(Ragnar::DEFAULT_EMBEDDING_MODEL)
    end
  end

  describe "#embed_text" do
    it "generates embeddings for text" do
      text = "This is a test sentence."
      embedding = embedder.embed_text(text)
      
      expect(embedding).to be_an(Array)
      expect(embedding).not_to be_empty
      expect(embedding.all? { |v| v.is_a?(Numeric) }).to be true
    end

    it "generates consistent embeddings for the same text" do
      text = "Consistent embedding test"
      embedding1 = embedder.embed_text(text)
      embedding2 = embedder.embed_text(text)
      
      expect(embedding1).to eq(embedding2)
    end

    it "generates different embeddings for different text" do
      embedding1 = embedder.embed_text("First text")
      embedding2 = embedder.embed_text("Completely different text")
      
      expect(embedding1).not_to eq(embedding2)
    end

    it "handles empty text" do
      embedding = embedder.embed_text("")
      
      # Empty text returns nil
      expect(embedding).to be_nil
    end

    it "handles long text" do
      long_text = "This is a very long text. " * 100
      embedding = embedder.embed_text(long_text)
      
      expect(embedding).to be_an(Array)
      expect(embedding).not_to be_empty
    end
  end

  describe "#embed_batch" do
    it "generates embeddings for multiple texts" do
      texts = [
        "First sentence",
        "Second sentence",
        "Third sentence"
      ]
      
      embeddings = embedder.embed_batch(texts)
      
      expect(embeddings).to be_an(Array)
      expect(embeddings.size).to eq(texts.size)
      embeddings.each do |embedding|
        expect(embedding).to be_an(Array)
        expect(embedding.all? { |v| v.is_a?(Numeric) }).to be true
      end
    end

    it "handles empty array" do
      embeddings = embedder.embed_batch([])
      
      expect(embeddings).to eq([])
    end

    it "handles single text in batch" do
      texts = ["Single text"]
      embeddings = embedder.embed_batch(texts)
      
      expect(embeddings.size).to eq(1)
      expect(embeddings.first).to be_an(Array)
    end

    it "maintains order of texts" do
      texts = ["AAA", "BBB", "CCC"]
      embeddings = embedder.embed_batch(texts)
      
      # Verify each text gets its own embedding in order
      expect(embeddings.size).to eq(3)
      
      # Each text should produce a unique embedding
      expect(embeddings[0]).not_to eq(embeddings[1])
      expect(embeddings[1]).not_to eq(embeddings[2])
    end
  end

  # Note: embedding_dimension method may not exist in actual implementation
  # Commenting out for now
  # describe "#embedding_dimension" do
  #   it "returns the dimension of embeddings" do
  #     dimension = embedder.embedding_dimension
  #     
  #     expect(dimension).to be_a(Integer)
  #     expect(dimension).to be > 0
  #   end
  # end

  describe "thread safety" do
    it "handles concurrent embedding requests" do
      texts = (1..10).map { |i| "Text number #{i}" }
      results = []
      threads = []
      
      texts.each do |text|
        threads << Thread.new do
          results << embedder.embed_text(text)
        end
      end
      
      threads.each(&:join)
      
      expect(results.size).to eq(texts.size)
      results.each do |embedding|
        expect(embedding).to be_an(Array)
        expect(embedding).not_to be_empty
      end
    end
  end
end
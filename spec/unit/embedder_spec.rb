# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ragnar::Embedder do
  let(:embedder) { described_class.new }
  
  describe "#initialize" do
    it "creates embedder with default model" do
      expect(embedder.model_name).to eq(Ragnar::DEFAULT_EMBEDDING_MODEL)
    end
    
    it "accepts custom model name" do
      suppress_output do
        custom = described_class.new(model_name: "custom/model")
        expect(custom.model_name).to eq("custom/model")
      end
    end
  end
  
  describe "#embed_text" do
    it "returns array of numbers for valid text" do
      embedding = embedder.embed_text("test text")
      
      expect(embedding).to be_an(Array)
      expect(embedding).not_to be_empty
      expect(embedding.all? { |v| v.is_a?(Numeric) }).to be true
    end
    
    it "returns nil for empty text" do
      expect(embedder.embed_text("")).to be_nil
      expect(embedder.embed_text(nil)).to be_nil
    end
    
    it "returns consistent embeddings for same text" do
      text = "consistent text"
      emb1 = embedder.embed_text(text)
      emb2 = embedder.embed_text(text)
      
      expect(emb1).to eq(emb2)
    end
    
    it "returns different embeddings for different text" do
      emb1 = embedder.embed_text("first text")
      emb2 = embedder.embed_text("second text")
      
      expect(emb1).not_to eq(emb2)
    end
  end
  
  describe "#embed_batch" do
    it "embeds multiple texts" do
      texts = ["text one", "text two", "text three"]
      embeddings = embedder.embed_batch(texts)
      
      expect(embeddings.size).to eq(3)
      embeddings.each do |emb|
        expect(emb).to be_an(Array)
        expect(emb.all? { |v| v.is_a?(Numeric) }).to be true
      end
    end
    
    it "maintains order of texts" do
      texts = ["alpha", "beta", "gamma"]
      embeddings = embedder.embed_batch(texts)
      
      # Each embedding should be unique and correspond to its text
      expect(embeddings[0]).to eq(embedder.embed_text("alpha"))
      expect(embeddings[1]).to eq(embedder.embed_text("beta"))
      expect(embeddings[2]).to eq(embedder.embed_text("gamma"))
    end
    
    it "handles empty array" do
      expect(embedder.embed_batch([])).to eq([])
    end
    
    it "handles array with nil/empty strings" do
      texts = ["valid", "", nil, "another"]
      embeddings = embedder.embed_batch(texts)
      
      expect(embeddings[0]).to be_an(Array)
      # Empty strings might return embeddings or nil depending on implementation
      expect(embeddings[1]).to be_nil.or be_an(Array)
      expect(embeddings[2]).to be_nil.or be_an(Array)
      expect(embeddings[3]).to be_an(Array)
    end
  end
end
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ragnar do
  it "has a version number" do
    expect(Ragnar::VERSION).not_to be nil
    expect(Ragnar::VERSION).to match(/\d+\.\d+\.\d+/)
  end

  describe "constants" do
    it "defines DEFAULT_DB_PATH" do
      expect(Ragnar::DEFAULT_DB_PATH).to eq("ragnar_database")
    end

    it "defines DEFAULT_CHUNK_SIZE" do
      expect(Ragnar::DEFAULT_CHUNK_SIZE).to eq(512)
    end

    it "defines DEFAULT_CHUNK_OVERLAP" do
      expect(Ragnar::DEFAULT_CHUNK_OVERLAP).to eq(50)
    end

    it "defines DEFAULT_EMBEDDING_MODEL" do
      expect(Ragnar::DEFAULT_EMBEDDING_MODEL).to eq("jinaai/jina-embeddings-v2-base-en")
    end

    it "defines DEFAULT_REDUCED_DIMENSIONS" do
      expect(Ragnar::DEFAULT_REDUCED_DIMENSIONS).to eq(64)
    end
  end

  describe "module structure" do
    it "loads all required classes" do
      expect(Ragnar::Database).to be_a(Class)
      expect(Ragnar::Chunker).to be_a(Class)
      expect(Ragnar::Embedder).to be_a(Class)
      expect(Ragnar::Indexer).to be_a(Class)
      expect(Ragnar::QueryProcessor).to be_a(Class)
      expect(Ragnar::CLI).to be_a(Class)
      expect(Ragnar::LLMManager).to be_a(Class)
      expect(Ragnar::ContextRepacker).to be_a(Class)
      expect(Ragnar::QueryRewriter).to be_a(Class)
      expect(Ragnar::UmapProcessor).to be_a(Class)
      expect(Ragnar::UmapTransformService).to be_a(Class)
    end

    it "loads topic modeling module" do
      expect(Ragnar::TopicModeling).to be_a(Module)
      expect(Ragnar::TopicModeling::Engine).to be_a(Class)
    end
  end

  describe "error handling" do
    it "defines custom error class" do
      expect(Ragnar::Error).to be < StandardError
    end

    it "can raise custom errors" do
      expect { raise Ragnar::Error, "Test error" }.to raise_error(Ragnar::Error, "Test error")
    end
  end
end
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ragnar::QueryRewriter do
  let(:mock_llm_manager) { double("LLMManager") }
  let(:mock_llm) { double("LLM") }
  let(:rewriter) { described_class.new(llm_manager: mock_llm_manager) }

  before do
    allow(mock_llm_manager).to receive(:default_llm).and_return(mock_llm)
  end

  describe "#initialize" do
    it "accepts custom LLM manager" do
      expect(rewriter.instance_variable_get(:@llm_manager)).to eq(mock_llm_manager)
    end

    it "uses default LLMManager when none provided" do
      allow(Ragnar::LLMManager).to receive(:instance).and_return(mock_llm_manager)
      
      default_rewriter = described_class.new
      expect(default_rewriter.instance_variable_get(:@llm_manager)).to eq(mock_llm_manager)
    end
  end

  describe "#rewrite" do
    let(:sample_query) { "What is machine learning?" }

    context "basic functionality" do
      it "returns a hash with required structure" do
        result = rewriter.rewrite(sample_query)

        expect(result).to be_a(Hash)
        expect(result).to have_key("clarified_intent")
        expect(result).to have_key("query_type") 
        expect(result).to have_key("sub_queries")
        expect(result).to have_key("key_terms")
        expect(result).to have_key("context_needed")
      end

      it "processes different types of queries" do
        queries = [
          "What is AI?",
          "How to implement neural networks?",
          "Compare supervised vs unsupervised learning",
          ""
        ]

        queries.each do |query|
          result = rewriter.rewrite(query)
          expect(result).to be_a(Hash)
          expect(result).to have_key("clarified_intent")
          expect(result).to have_key("sub_queries")
        end
      end

      it "handles edge cases" do
        edge_cases = ["", nil, "   ", "A", "Very long query with many words that should test the system thoroughly"]

        edge_cases.each do |query|
          expect {
            result = rewriter.rewrite(query || "")
            expect(result).to be_a(Hash)
          }.not_to raise_error
        end
      end
    end

    context "with mocked LLM responses" do

      it "returns structured data types" do
        result = rewriter.rewrite(sample_query)

        expect(result["clarified_intent"]).to be_a(String)
        expect(result["query_type"]).to be_a(String)
        expect(result["sub_queries"]).to be_an(Array)
        expect(result["key_terms"]).to be_an(Array)
        expect(result["context_needed"]).to be_a(String)
      end

      it "handles arrays in response" do
        result = rewriter.rewrite(sample_query)

        expect(result["sub_queries"]).to be_an(Array)
        expect(result["key_terms"]).to be_an(Array)
        
        # Arrays should contain strings
        if result["sub_queries"].any?
          expect(result["sub_queries"]).to all(be_a(String))
        end
        
        if result["key_terms"].any?
          expect(result["key_terms"]).to all(be_a(String))
        end
      end
    end

    context "error handling" do
      it "handles LLM manager failures" do
        allow(mock_llm_manager).to receive(:default_llm).and_raise("LLM Manager error")

        expect {
          result = rewriter.rewrite(sample_query)
          expect(result).to be_a(Hash)
        }.not_to raise_error
      end

      it "handles LLM generation failures" do
        error_llm = double("Error LLM")
        allow(error_llm).to receive(:generate_structured).and_raise("Generation failed")
        allow(mock_llm_manager).to receive(:default_llm).and_return(error_llm)

        expect {
          result = rewriter.rewrite(sample_query)
          expect(result).to be_a(Hash)
        }.not_to raise_error
      end
    end

    context "response validation" do
      it "ensures response has all required keys" do
        result = rewriter.rewrite(sample_query)

        required_keys = ["clarified_intent", "query_type", "sub_queries", "key_terms", "context_needed"]
        required_keys.each do |key|
          expect(result).to have_key(key), "Missing required key: #{key}"
        end
      end

      it "handles different query lengths" do
        short_query = "AI"
        long_query = "Explain the differences between supervised learning, unsupervised learning, and reinforcement learning in machine learning, including examples and use cases"

        [short_query, long_query].each do |query|
          result = rewriter.rewrite(query)
          expect(result).to be_a(Hash)
          expect(result["clarified_intent"]).to be_a(String)
          expect(result["sub_queries"]).to be_an(Array)
        end
      end
    end

    context "integration with LLM system" do

      it "processes queries without raising errors" do
        test_queries = [
          "What is deep learning?",
          "How to train neural networks?", 
          "Compare TensorFlow vs PyTorch",
          "Best practices for data preprocessing"
        ]

        test_queries.each do |query|
          expect {
            result = rewriter.rewrite(query)
            expect(result).to be_a(Hash)
          }.not_to raise_error
        end
      end
    end
  end
end
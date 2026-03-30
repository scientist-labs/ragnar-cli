# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ragnar::Tools::SearchDocs do
  let(:tool) { described_class.new }
  let(:mock_processor) { instance_double(Ragnar::QueryProcessor) }

  before do
    allow(Ragnar::QueryProcessor).to receive(:new).and_return(mock_processor)
  end

  describe "#execute" do
    it "returns formatted search results" do
      allow(mock_processor).to receive(:retrieve_context).and_return({
        context: "Passwords must be at least 12 characters.",
        sources: [
          { source_file: "/docs/Password Policy.docx", chunk_index: 0 }
        ],
        confidence: 85.5,
        clarified: "password policy"
      })

      result = tool.execute(query: "What is our password policy?")
      expect(result).to include("Retrieved Context")
      expect(result).to include("Passwords must be at least 12 characters")
      expect(result).to include("Password Policy.docx")
      expect(result).to include("85.5%")
    end

    it "handles empty results" do
      allow(mock_processor).to receive(:retrieve_context).and_return({
        context: "",
        sources: [],
        confidence: 0.0,
        clarified: "query"
      })

      result = tool.execute(query: "something not indexed")
      expect(result).to include("No relevant documents found")
    end

    it "handles errors gracefully" do
      allow(mock_processor).to receive(:retrieve_context)
        .and_raise("Database connection failed")

      result = tool.execute(query: "test")
      expect(result).to include("Error searching documents")
    end
  end

  describe "tool metadata" do
    it "has a description mentioning knowledge base" do
      expect(tool.description).to include("knowledge base")
    end

    it "has a name" do
      expect(tool.name).to include("search_docs")
    end
  end
end

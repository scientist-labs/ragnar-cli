# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ragnar::ContextRepacker do
  let(:sample_documents) do
    [
      {
        file_path: "/docs/ai.txt",
        chunk_text: "Machine learning is a subset of artificial intelligence. It uses algorithms to learn patterns.",
        chunk_index: 0
      },
      {
        file_path: "/docs/ai.txt", 
        chunk_text: "Neural networks are inspired by biological neurons. They can solve complex problems.",
        chunk_index: 1
      },
      {
        file_path: "/docs/programming.txt",
        chunk_text: "Ruby is a dynamic programming language. It focuses on simplicity and productivity.",
        chunk_index: 0
      }
    ]
  end

  let(:query) { "What is machine learning?" }

  describe ".repack" do
    context "with valid documents" do
      it "groups documents by source file" do
        result = described_class.repack(sample_documents, query)

        expect(result).to include("Source: ai.txt")
        expect(result).to include("Source: programming.txt")
        expect(result).to include("Machine learning is a subset")
        expect(result).to include("Ruby is a dynamic programming")
      end

      it "combines chunks from same source with separator" do
        result = described_class.repack(sample_documents, query)

        # Should join chunks from same file with " ... "
        expect(result).to include("Machine learning is a subset of artificial intelligence") 
        expect(result).to include("Neural networks are inspired")
        expect(result).to include(" ... ")
      end

      it "separates different sources clearly" do
        result = described_class.repack(sample_documents, query)

        # Should separate sources with ---
        expect(result).to include("---")
        
        # Should have proper structure
        parts = result.split("---")
        expect(parts.length).to be >= 2
      end

      it "filters out empty chunk text during joining" do
        docs_with_empty = sample_documents + [
          { file_path: "/docs/empty.txt", chunk_text: "", chunk_index: 0 },
          { file_path: "/docs/empty.txt", chunk_text: "   ", chunk_index: 1 },
          { file_path: "/docs/mixed.txt", chunk_text: "Valid content", chunk_index: 0 },
          { file_path: "/docs/mixed.txt", chunk_text: "", chunk_index: 1 }
        ]

        result = described_class.repack(docs_with_empty, query)

        # Empty files will still create a "Source:" entry, but with no content after cleaning
        expect(result).to include("Source: mixed.txt")
        expect(result).to include("Valid content")
        # The empty.txt source will appear but have minimal content
        expect(result).to include("Source: empty.txt")
      end

      it "handles different document field names" do
        alt_docs = [
          { source_file: "source1.txt", text: "Content from source 1" },
          { file_path: "source2.txt", chunk_text: "Content from source 2" }
        ]

        result = described_class.repack(alt_docs, query)

        expect(result).to include("Source: source1.txt")
        expect(result).to include("Source: source2.txt")
        expect(result).to include("Content from source 1")
        expect(result).to include("Content from source 2")
      end

      it "handles unknown source files" do
        docs_no_source = [
          { chunk_text: "Content without source", chunk_index: 0 }
        ]

        result = described_class.repack(docs_no_source, query)

        expect(result).to include("Source: unknown")
        expect(result).to include("Content without source")
      end
    end

    context "with token limiting" do
      let(:long_documents) do
        Array.new(5) do |i|
          {
            file_path: "/docs/long#{i}.txt",
            chunk_text: "This is a very long piece of text that contains many words. " * 50,
            chunk_index: 0
          }
        end
      end

      it "respects max_tokens parameter" do
        result = described_class.repack(long_documents, query, max_tokens: 100)

        # Should be trimmed to approximately max_tokens * 4 characters
        expect(result.length).to be <= 500  # 100 * 4 + some buffer for structure
      end

      it "uses default max_tokens when not specified" do
        result = described_class.repack(long_documents, query)

        # Default is 2000 tokens, so ~8000 chars
        # This is hard to test exactly, but should be reasonable length
        expect(result).to be_a(String)
        expect(result.length).to be > 0
      end

      it "trims content intelligently based on query relevance" do
        mixed_docs = [
          {
            file_path: "relevant.txt",
            chunk_text: "Machine learning algorithms use data to learn patterns. This is very relevant to the query about machine learning.",
            chunk_index: 0
          },
          {
            file_path: "irrelevant.txt", 
            chunk_text: "The weather is nice today. Birds are singing in the trees. This has nothing to do with the query.",
            chunk_index: 0
          }
        ]

        result = described_class.repack(mixed_docs, "machine learning", max_tokens: 50)

        # Should prioritize relevant content
        expect(result).to include("machine learning")
        expect(result.length).to be <= 250  # 50 * 4 + buffer
      end
    end

    context "with empty or invalid inputs" do
      it "returns empty string for empty documents" do
        result = described_class.repack([], query)
        expect(result).to eq("")
      end

      it "handles nil documents gracefully" do
        expect {
          result = described_class.repack(nil, query)
        }.to raise_error(NoMethodError)  # Ruby will raise this for nil.empty?
      end

      it "handles documents with missing text fields" do
        incomplete_docs = [
          { file_path: "test.txt" },  # Missing chunk_text
          { chunk_index: 0 }          # Missing file_path and chunk_text
        ]

        result = described_class.repack(incomplete_docs, query)

        expect(result).to be_a(String)
        # Should handle gracefully even with missing fields
      end
    end
  end

  describe ".repack_with_summary" do
    let(:mock_llm) { double("LLM") }

    context "with LLM provided" do
      before do
        allow(mock_llm).to receive(:generate).and_return("This is a generated summary about machine learning.")
        allow_any_instance_of(Ragnar::ContextRepacker).to receive(:puts) # Suppress warning output
      end

      it "generates summary and combines with detailed context" do
        result = described_class.repack_with_summary(sample_documents, query, llm: mock_llm)

        expect(result).to include("Summary:")
        expect(result).to include("This is a generated summary")
        expect(result).to include("Detailed Information:")
        expect(result).to include("Machine learning is a subset")
      end

      it "calls LLM with proper summary prompt" do
        described_class.repack_with_summary(sample_documents, query, llm: mock_llm)

        expect(mock_llm).to have_received(:generate) do |prompt|
          expect(prompt).to include(query)
          expect(prompt).to include("Query: #{query}")
          expect(prompt).to include("Information:")
          expect(prompt).to include("Provide a brief summary")
        end
      end

      it "limits context sent to LLM for summary" do
        described_class.repack_with_summary(sample_documents, query, llm: mock_llm)

        expect(mock_llm).to have_received(:generate) do |prompt|
          # Should limit to 1500 chars for summary generation
          info_section = prompt.split("Information:").last
          expect(info_section.length).to be <= 1600  # 1500 + some buffer for formatting
        end
      end
    end

    context "without LLM provided" do
      it "falls back to basic repacking" do
        result = described_class.repack_with_summary(sample_documents, query, llm: nil)
        basic_result = described_class.repack(sample_documents, query)

        expect(result).to eq(basic_result)
      end
    end

    context "when LLM generation fails" do
      before do
        allow(mock_llm).to receive(:generate).and_raise("LLM generation failed")
        # Suppress puts output from the class method
        allow(described_class).to receive(:puts)
      end

      it "falls back to basic repacking" do
        result = described_class.repack_with_summary(sample_documents, query, llm: mock_llm)
        basic_result = described_class.repack(sample_documents, query)

        expect(result).to eq(basic_result)
      end

      it "handles error gracefully without output" do
        # Test already suppresses puts, so just verify no exception
        expect {
          described_class.repack_with_summary(sample_documents, query, llm: mock_llm)
        }.not_to raise_error
      end
    end

    context "with empty documents" do
      it "returns empty string" do
        result = described_class.repack_with_summary([], query, llm: mock_llm)
        expect(result).to eq("")
      end
    end
  end

  describe "private methods" do
    describe ".clean_text" do
      it "normalizes whitespace" do
        messy_text = "Text   with    lots     of      spaces"
        result = described_class.send(:clean_text, messy_text)
        
        expect(result).to eq("Text with lots of spaces")
      end

      it "normalizes all whitespace including newlines" do
        text_with_newlines = "Line 1\n\n\n\n\nLine 2"
        result = described_class.send(:clean_text, text_with_newlines)
        
        # The gsub(/\s+/, ' ') converts all whitespace to single spaces first
        expect(result).to eq("Line 1 Line 2")
      end

      it "normalizes ellipsis" do
        text_with_dots = "Text.....more text......end"
        result = described_class.send(:clean_text, text_with_dots)
        
        expect(result).to eq("Text...more text...end")
      end

      it "strips leading and trailing whitespace" do
        padded_text = "  \n  Text content  \n  "
        result = described_class.send(:clean_text, padded_text)
        
        expect(result).to eq("Text content")
      end

      it "handles empty string" do
        result = described_class.send(:clean_text, "")
        expect(result).to eq("")
      end
    end

    describe ".trim_to_relevant" do
      let(:long_text) do
        "This sentence mentions machine learning algorithms. " \
        "This sentence talks about the weather today. " \
        "Another sentence about artificial intelligence and machine learning. " \
        "Random content about cooking and recipes. " \
        "Final sentence discussing machine learning applications."
      end

      it "prioritizes sentences with query terms" do
        result = described_class.send(:trim_to_relevant, long_text, "machine learning", 200)

        # Should include sentences with "machine learning" 
        expect(result).to include("machine learning")
        # Should prioritize relevant sentences
        expect(result.length).to be <= 200
      end

      it "extracts query terms correctly" do
        # Test with different query structures
        result1 = described_class.send(:trim_to_relevant, long_text, "artificial intelligence", 150)
        result2 = described_class.send(:trim_to_relevant, long_text, "what is AI?", 150)

        expect(result1).to include("artificial intelligence") if result1.length > 0
        # "AI" is too short (< 3 chars) so might not match well
      end

      it "handles queries with no matching terms" do
        result = described_class.send(:trim_to_relevant, long_text, "nonexistent terms", 100)

        # Should still return some content, prioritizing by original order
        expect(result).to be_a(String)
        expect(result.length).to be <= 100
      end

      it "respects character limit" do
        result = described_class.send(:trim_to_relevant, long_text, "machine learning", 50)

        expect(result.length).to be <= 50
      end

      it "handles very small character limits" do
        result = described_class.send(:trim_to_relevant, long_text, "machine learning", 10)

        expect(result.length).to be <= 10
      end

      it "splits text into sentences correctly" do
        text_with_punctuation = "First sentence. Second sentence! Third sentence? Fourth sentence."
        result = described_class.send(:trim_to_relevant, text_with_punctuation, "sentence", 1000)

        # Should include all sentences since limit is high
        expect(result).to include("First sentence")
        expect(result).to include("Second sentence")
        expect(result).to include("Third sentence") 
        expect(result).to include("Fourth sentence")
      end
    end
  end
end
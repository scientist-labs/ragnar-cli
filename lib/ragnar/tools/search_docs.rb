# frozen_string_literal: true

module Ragnar
  module Tools
    # SearchDocs bridges the RAG pipeline into the Agent's tool set.
    #
    # This is how the Agent accesses indexed knowledge — company documents,
    # policies, technical docs, anything that's been indexed with `ragnar index`.
    #
    # Key design decision: this tool returns the RETRIEVED CONTEXT (document
    # chunks + sources), not an LLM-generated answer. The Agent synthesizes
    # the answer itself using the context plus its full conversation history.
    # This avoids a double-LLM problem where the RAG pipeline generates an
    # answer and the Agent then paraphrases it.
    class SearchDocs < RubyLLM::Tool
      description "Search the indexed knowledge base for information. Use this when the user " \
                  "asks questions about documents, policies, procedures, or any previously " \
                  "indexed content. Returns relevant document excerpts with source citations."

      param :query, desc: "The search query — what information to find"
      param :top_k, desc: "Number of results to return (default: 5)", type: :integer, required: false

      def execute(query:, top_k: 5)
        config = Config.instance
        processor = QueryProcessor.new(db_path: config.database_path)
        result = processor.retrieve_context(
          query,
          top_k: top_k || 5,
          enable_rewriting: config.enable_query_rewriting?,
          enable_reranking: config.enable_reranking?
        )

        if result[:context].empty?
          return "No relevant documents found for: #{query}"
        end

        output = "## Retrieved Context\n\n"
        output += result[:context]
        output += "\n\n## Sources\n"
        result[:sources].each_with_index do |s, i|
          output += "#{i + 1}. #{s[:source_file]}"
          output += " (chunk #{s[:chunk_index]})" if s[:chunk_index]
          output += "\n"
        end
        output += "\nConfidence: #{result[:confidence]}%"
        output
      rescue => e
        "Error searching documents: #{e.message}"
      end
    end
  end
end

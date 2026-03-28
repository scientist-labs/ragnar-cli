module Ragnar
  class QueryRewriter
    def initialize(llm_manager: nil)
      @llm_manager = llm_manager || LLMManager.instance
    end

    def rewrite(query)
      # Create a fresh chat for each rewrite to avoid conversation history bleed
      chat = Config.instance.create_chat

      # Define the JSON schema for structured output
      schema = {
        type: "object",
        properties: {
          clarified_intent: {
            type: "string",
            description: "A clear, specific statement of what the user is looking for"
          },
          query_type: {
            type: "string",
            enum: ["factual", "conceptual", "procedural", "comparative", "analytical"],
            description: "The type of query"
          },
          sub_queries: {
            type: "array",
            items: { type: "string" },
            minItems: 2,
            maxItems: 5,
            description: "Simpler, focused queries that together answer the main query"
          },
          key_terms: {
            type: "array",
            items: { type: "string" },
            description: "Important terms and their synonyms for searching"
          },
          context_needed: {
            type: "string",
            enum: ["minimal", "moderate", "extensive"],
            description: "How much context is likely needed to answer this query"
          }
        },
        required: ["clarified_intent", "query_type", "sub_queries", "key_terms", "context_needed"]
      }

      prompt = <<~PROMPT
        Analyze the following user query and break it down for retrieval-augmented generation.
        Focus on understanding the user's intent and creating effective sub-queries for searching.

        User Query: #{query}

        Provide a structured analysis that will help retrieve the most relevant documents. /no_think
      PROMPT

      begin
        response = chat.with_schema(schema).ask(prompt)
        result = response.content

        # RubyLLM with_schema returns parsed content; handle both String and Hash
        if result.is_a?(String)
          JSON.parse(result)
        elsif result.is_a?(Hash)
          result.transform_keys(&:to_s)
        else
          result
        end
      rescue => e
        # Fallback to simple rewriting if structured generation fails
        {
          "clarified_intent" => query,
          "query_type" => "general",
          "sub_queries" => [query],
          "key_terms" => query.split(/\s+/).select { |w| w.length > 3 },
          "context_needed" => "moderate"
        }
      end
    end
  end
end

module RubyRag
  class QueryRewriter
    def initialize(llm_manager: nil)
      @llm_manager = llm_manager || LLMManager.instance
    end
    
    def rewrite(query)
      # Get the cached LLM
      model = @llm_manager.default_llm
      
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
        
        Provide a structured analysis that will help retrieve the most relevant documents.
      PROMPT
      
      begin
        # Use structured generation with schema
        result = model.generate_structured(
          prompt,
          schema: schema
        )
        
        # The result should already be a JSON string
        JSON.parse(result)
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
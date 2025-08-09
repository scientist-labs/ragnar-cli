module RubyRag
  class QueryRewriter
    def initialize(model_id: nil)
      @model_id = model_id || "TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF"
      @model = nil
    end
    
    def rewrite(query)
      # Load the model lazily
      @model ||= Candle::LLM.from_pretrained(
        @model_id,
        gguf_file: "tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf"
      )
      
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
        result = @model.generate_structured(
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
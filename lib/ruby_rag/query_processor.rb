require 'json'

module RubyRag
  class QueryProcessor
    attr_reader :database, :embedder, :rewriter, :reranker
    
    def initialize(db_path: RubyRag::DEFAULT_DB_PATH)
      @database = Database.new(db_path)
      @embedder = Embedder.new
      @llm_manager = LLMManager.instance
      @rewriter = QueryRewriter.new(llm_manager: @llm_manager)
      @reranker = nil # Will initialize when needed
    end
    
    def query(user_query, top_k: 3, verbose: false)
      puts "Processing query: #{user_query}" if verbose
      
      # Step 1: Rewrite and analyze the query
      puts "\n1. Analyzing query..." if verbose
      rewritten = @rewriter.rewrite(user_query)
      
      if verbose
        puts "   Clarified intent: #{rewritten['clarified_intent']}"
        puts "   Query type: #{rewritten['query_type']}"
        puts "   Sub-queries:"
        rewritten['sub_queries'].each { |sq| puts "     - #{sq}" }
      end
      
      # Step 2: Retrieve candidates using RRF
      puts "\n2. Retrieving documents..." if verbose
      candidates = retrieve_with_rrf(
        rewritten['sub_queries'],
        k: 20,
        verbose: verbose
      )
      
      if candidates.empty?
        return {
          query: user_query,
          clarified: rewritten['clarified_intent'],
          answer: "No relevant documents found in the database.",
          sources: []
        }
      end
      
      puts "   Found #{candidates.size} candidate documents" if verbose
      
      # Step 3: Rerank candidates
      puts "\n3. Reranking documents..." if verbose
      reranked = rerank_documents(
        query: rewritten['clarified_intent'],
        documents: candidates,
        top_k: top_k * 2  # Get more than we need for context
      )
      
      # Step 4: Prepare context with neighboring chunks
      puts "\n4. Preparing context..." if verbose
      context_docs = prepare_context(reranked[0...top_k], rewritten['context_needed'])
      
      # Step 5: Repack context for optimal LLM consumption
      puts "\n5. Repacking context..." if verbose
      repacked_context = ContextRepacker.repack(
        context_docs,
        rewritten['clarified_intent']
      )
      
      if verbose
        puts "   Original context size: #{context_docs.sum { |d| (d[:chunk_text] || "").length }} chars"
        puts "   Repacked context size: #{repacked_context.length} chars"
      end
      
      # Step 6: Generate response
      puts "\n6. Generating response..." if verbose
      response = generate_response(
        query: rewritten['clarified_intent'],
        repacked_context: repacked_context,
        query_type: rewritten['query_type']
      )
      
      {
        query: user_query,
        clarified: rewritten['clarified_intent'],
        answer: response,
        sources: context_docs.map { |d| 
          {
            source_file: d[:file_path] || d[:source_file],
            chunk_index: d[:chunk_index]
          }
        },
        sub_queries: rewritten['sub_queries'],
        confidence: calculate_confidence(reranked[0...top_k])
      }
    end
    
    private
    
    def retrieve_with_rrf(queries, k: 20, verbose: false)
      all_results = []
      
      queries.each_with_index do |query, idx|
        puts "   Searching: #{query}" if verbose
        
        # Generate embedding for the query
        query_embedding = @embedder.embed_text(query)
        
        # Vector search
        vector_results = @database.search_similar(
          query_embedding,
          k: k
        )
        
        # Add query index for RRF
        vector_results.each do |result|
          result[:query_idx] = idx
          result[:retrieval_method] = :vector
        end
        
        all_results.concat(vector_results)
      end
      
      # Apply Reciprocal Rank Fusion
      apply_rrf(all_results, k: k)
    end
    
    def apply_rrf(results, k: 60)
      # Group by document ID
      doc_scores = {}
      
      results.each do |result|
        doc_id = result[:id]
        doc_scores[doc_id] ||= {
          score: 0.0,
          document: result
        }
        
        # RRF formula: 1 / (k + rank)
        # Using distance as a proxy for rank (lower distance = better rank)
        rank = result[:distance] * 100  # Scale distance to rank-like values
        doc_scores[doc_id][:score] += 1.0 / (k + rank)
      end
      
      # Sort by RRF score and return documents
      doc_scores.values
        .sort_by { |item| -item[:score] }
        .map { |item| item[:document] }
    end
    
    def rerank_documents(query:, documents:, top_k:)
      # Initialize reranker if not already done
      @reranker ||= Candle::Reranker.new(
        model_path: "cross-encoder/ms-marco-MiniLM-L-12-v2"
      )
      
      # Prepare document texts - use chunk_text field
      texts = documents.map { |doc| doc[:chunk_text] || doc[:text] || "" }
      
      # Rerank - returns array of {doc_id:, score:, text:}
      reranked = @reranker.rerank(query, texts)
      
      # Map back to original documents with scores
      reranked.map do |result|
        doc_idx = result[:doc_id]
        documents[doc_idx]
      end.first(top_k)
    rescue => e
      puts "Warning: Reranking failed (#{e.message}), using original order"
      documents.first(top_k)
    end
    
    def prepare_context(documents, context_needed)
      # For now, just return the documents
      # In the future, we could fetch neighboring chunks for more context
      context_size = case context_needed
                     when "extensive" then 5
                     when "moderate" then 3
                     else 2
                     end
      
      documents.first(context_size)
    end
    
    def generate_response(query:, repacked_context:, query_type:)
      # Get cached LLM from manager
      llm = @llm_manager.default_llm
      
      # Create prompt with repacked context
      prompt = build_prompt(query, repacked_context, query_type)
      
      # Generate response using default config
      llm.generate(prompt)
    rescue => e
      # Fallback to returning the repacked context
      puts "Warning: LLM generation failed (#{e.message})"
      "Based on the retrieved information:\n\n#{repacked_context[0..500]}..."
    end
    
    def build_prompt(query, context, query_type)
      base_prompt = <<~PROMPT
        <|system|>
        You are a helpful assistant. Answer questions based ONLY on the provided context.
        If the answer is not in the context, say "I don't have enough information to answer that question."
        </s>
        <|user|>
        Context:
        #{context}
        
        Question: #{query}
        </s>
        <|assistant|>
      PROMPT
      
      base_prompt
    end
    
    def calculate_confidence(documents)
      return 0.0 if documents.empty?
      
      # Simple confidence based on average similarity
      avg_distance = documents.map { |d| d[:distance] }.sum / documents.size
      
      # Convert distance to confidence (0-1 scale)
      # Assuming distances are typically 0-2
      confidence = [1.0 - (avg_distance / 2.0), 0.0].max
      (confidence * 100).round(1)
    end
  end
end
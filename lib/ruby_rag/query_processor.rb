require 'json'

module RubyRag
  class QueryProcessor
    attr_reader :database, :embedder, :rewriter, :reranker
    
    def initialize(db_path: RubyRag::DEFAULT_DB_PATH)
      @database = Database.new(db_path)
      @embedder = Embedder.new
      @rewriter = QueryRewriter.new
      @reranker = nil # Will initialize when needed
      @llm = nil # Will initialize when needed
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
      
      # Step 5: Generate response
      puts "\n5. Generating response..." if verbose
      response = generate_response(
        query: rewritten['clarified_intent'],
        documents: context_docs,
        query_type: rewritten['query_type']
      )
      
      {
        query: user_query,
        clarified: rewritten['clarified_intent'],
        answer: response,
        sources: context_docs.map { |d| d[:metadata] },
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
        query_embedding = @embedder.embed(query)
        
        # Vector search
        vector_results = @database.search(
          embedding: query_embedding,
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
        model_id: "BAAI/bge-reranker-base"
      )
      
      # Prepare document texts
      texts = documents.map { |doc| doc[:text] }
      
      # Rerank
      scores = @reranker.rerank(
        query: query,
        documents: texts
      )
      
      # Combine scores with documents and sort
      documents.zip(scores)
        .sort_by { |_, score| -score }
        .map(&:first)
        .first(top_k)
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
    
    def generate_response(query:, documents:, query_type:)
      # Initialize LLM if not already done
      @llm ||= Candle::Model.new(
        model_id: "Qwen/Qwen2.5-1.5B-Instruct",
        dtype: "f32"
      )
      
      # Prepare context from documents
      context = documents.map.with_index do |doc, idx|
        "Document #{idx + 1}:\n#{doc[:text]}\n"
      end.join("\n")
      
      # Create prompt based on query type
      prompt = build_prompt(query, context, query_type)
      
      # Generate response
      @llm.generate(
        prompt: prompt,
        max_tokens: 500,
        temperature: 0.7
      )
    rescue => e
      # Fallback to simple concatenation if LLM fails
      "Based on the retrieved documents:\n\n" +
      documents.map { |d| "- #{d[:text][0..200]}..." }.join("\n\n")
    end
    
    def build_prompt(query, context, query_type)
      base_prompt = <<~PROMPT
        You are a helpful assistant answering questions based on provided context.
        
        Context:
        #{context}
        
        Question: #{query}
      PROMPT
      
      case query_type
      when "factual"
        base_prompt + "\nProvide a direct, factual answer based on the context."
      when "analytical"
        base_prompt + "\nAnalyze the information and provide insights."
      when "comparative"
        base_prompt + "\nCompare and contrast the relevant information."
      when "procedural"
        base_prompt + "\nProvide step-by-step instructions or process description."
      else
        base_prompt + "\nAnswer the question based on the context provided."
      end
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
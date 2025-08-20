require 'json'
require 'singleton'

module RubyRag
  class QueryProcessor
    attr_reader :database, :embedder, :rewriter, :reranker
    
    def initialize(db_path: RubyRag::DEFAULT_DB_PATH)
      @database = Database.new(db_path)
      @embedder = Embedder.new
      @llm_manager = LLMManager.instance
      @umap_service = UmapTransformService.instance
      @rewriter = QueryRewriter.new(llm_manager: @llm_manager)
      @reranker = nil # Will initialize when needed
    end
    
    def query(user_query, top_k: 3, verbose: false)
      puts "Processing query: #{user_query}" if verbose
      
      # Step 1: Rewrite and analyze the query
      puts "\n#{'-'*60}" if verbose
      puts "STEP 1: Query Analysis & Rewriting" if verbose
      puts "-"*60 if verbose
      
      rewritten = @rewriter.rewrite(user_query)
      
      if verbose
        puts "\nOriginal Query: #{user_query}"
        puts "\nRewritten Query Analysis:"
        puts "  Clarified Intent: #{rewritten['clarified_intent']}"
        puts "  Query Type: #{rewritten['query_type']}"
        puts "  Context Needed: #{rewritten['context_needed']}"
        puts "\nGenerated Sub-queries (#{rewritten['sub_queries'].length}):"
        rewritten['sub_queries'].each_with_index do |sq, idx|
          puts "  #{idx + 1}. #{sq}"
        end
        if rewritten['key_terms'] && !rewritten['key_terms'].empty?
          puts "\nKey Terms Identified:"
          puts "  #{rewritten['key_terms'].join(', ')}"
        end
      end
      
      # Step 2: Retrieve candidates using RRF
      if verbose
        puts "\n#{'-'*60}"
        puts "STEP 2: Document Retrieval with RRF"
        puts "-"*60
      end
      
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
      
      if verbose
        puts "\nRetrieval Summary:"
        puts "  Total candidates found: #{candidates.size}"
        puts "  Unique sources: #{candidates.map { |c| c[:file_path] }.uniq.size}"
      end
      
      # Step 3: Rerank candidates
      if verbose
        puts "\n#{'-'*60}"
        puts "STEP 3: Document Reranking"
        puts "-"*60
      end
      
      reranked = rerank_documents(
        query: rewritten['clarified_intent'],
        documents: candidates,
        top_k: top_k * 2  # Get more than we need for context
      )
      
      if verbose && reranked.any?
        puts "\nTop Reranked Documents:"
        reranked[0..2].each_with_index do |doc, idx|
          full_text = (doc[:chunk_text] || doc[:text] || "").gsub(/\s+/, ' ')
          puts "  #{idx + 1}. [#{File.basename(doc[:file_path] || 'unknown')}]"
          puts "     Score: #{doc[:score]&.round(4) if doc[:score]}"
          puts "     Full chunk (#{full_text.length} chars):"
          puts "     \"#{full_text}\""
          puts ""
        end
      end
      
      # Step 4: Prepare context with neighboring chunks
      if verbose
        puts "\n#{'-'*60}"
        puts "STEP 4: Context Preparation"
        puts "-"*60
      end
      
      context_docs = prepare_context(reranked[0...top_k], rewritten['context_needed'])
      
      if verbose
        puts "\nContext Documents Selected: #{context_docs.length}"
        puts "Context strategy: #{rewritten['context_needed']}"
      end
      
      # Step 5: Repack context for optimal LLM consumption
      if verbose
        puts "\n#{'-'*60}"
        puts "STEP 5: Context Repacking"
        puts "-"*60
      end
      
      repacked_context = ContextRepacker.repack(
        context_docs,
        rewritten['clarified_intent']
      )
      
      if verbose
        original_size = context_docs.sum { |d| (d[:chunk_text] || "").length }
        puts "\nContext Optimization:"
        puts "  Original size: #{original_size} chars"
        puts "  Repacked size: #{repacked_context.length} chars"
        puts "  Compression ratio: #{(100.0 * repacked_context.length / original_size).round(1)}%"
        puts "\nFull Repacked Context:"
        puts "-" * 40
        puts repacked_context
        puts "-" * 40
      end
      
      # Step 6: Generate response
      if verbose
        puts "\n#{'-'*60}"
        puts "STEP 6: Response Generation"
        puts "-"*60
      end
      response = generate_response(
        query: rewritten['clarified_intent'],
        repacked_context: repacked_context,
        query_type: rewritten['query_type']
      )
      
      if verbose
        puts "\nGenerated Response:"
        puts "-" * 40
        puts response
        puts "-" * 40
      end
      
      result = {
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
      
      if verbose
        puts "\n#{'-'*60}"
        puts "FINAL RESULTS"
        puts "-"*60
        puts "\nConfidence Score: #{result[:confidence]}%"
        puts "\nSources Used:"
        result[:sources].each_with_index do |source, idx|
          puts "  #{idx + 1}. #{source[:source_file]} (chunk #{source[:chunk_index]})"
        end
      end
      
      result
    end
    
    private
    
    def retrieve_with_rrf(queries, k: 20, verbose: false)
      all_results = []
      
      queries.each_with_index do |query, idx|
        if verbose
          puts "\nSub-query #{idx + 1}: \"#{query}\""
          puts "  Generating embedding..."
        end
        
        # Generate embedding for the query
        query_embedding = @embedder.embed_text(query)
        
        if verbose
          puts "  Embedding dimensions: #{query_embedding.length}"
          puts "  Searching vector database..."
        end
        
        # Check if we have reduced embeddings available for more efficient search
        stats = @database.get_stats
        use_reduced = stats[:with_reduced_embeddings] > 0
        
        # Prepare the search embedding (either full or reduced)
        search_embedding = query_embedding
        
        if use_reduced
          # Check if UMAP model is available
          model_path = "./umap_model.bin"
          
          if @umap_service.model_available?(model_path)
            if verbose
              puts "  Transforming query to reduced space (#{stats[:reduced_dims]}D)"
            end
            
            begin
              # Transform the query embedding to reduced space
              search_embedding = @umap_service.transform_query(query_embedding, model_path)
              
              if verbose
                puts "  ✓ Query transformed to #{search_embedding.size}D"
                puts "  Searching with reduced embeddings..."
              end
            rescue => e
              puts "  ⚠️  Failed to transform query: #{e.message}" if verbose
              puts "  Falling back to full embeddings" if verbose
              use_reduced = false
            end
          else
            if verbose
              puts "  Note: Reduced embeddings available but UMAP model not found"
              puts "  Falling back to full embeddings"
            end
            use_reduced = false
          end
        end
        
        vector_results = @database.search_similar(
          search_embedding,
          k: k,
          use_reduced: use_reduced
        )
        
        if verbose
          puts "  Found #{vector_results.length} matches"
          if vector_results.any?
            best = vector_results.first
            puts "  Best match: [#{File.basename(best[:file_path] || 'unknown')}] (distance: #{best[:distance]&.round(3)})"
          end
        end
        
        # Add query index for RRF
        vector_results.each do |result|
          result[:query_idx] = idx
          result[:retrieval_method] = :vector
        end
        
        all_results.concat(vector_results)
      end
      
      if verbose
        puts "\nApplying Reciprocal Rank Fusion..."
        puts "  Total results before fusion: #{all_results.length}"
      end
      
      # Apply Reciprocal Rank Fusion
      fused = apply_rrf(all_results, k: k)
      
      if verbose
        puts "  Results after RRF: #{fused.length}"
      end
      
      fused
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
      @reranker ||= Candle::Reranker.from_pretrained(
        "cross-encoder/ms-marco-MiniLM-L-12-v2"
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
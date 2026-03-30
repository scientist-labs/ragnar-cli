require 'json'
require 'singleton'
require 'set'
require 'digest'

module Ragnar
  class QueryProcessor
    attr_reader :database, :embedder, :rewriter, :reranker
    
    def initialize(db_path: Ragnar::DEFAULT_DB_PATH)
      @database = Database.new(db_path)
      @embedder = Embedder.new
      @llm_manager = LLMManager.instance
      @umap_service = UmapTransformService.instance
      @rewriter = QueryRewriter.new(llm_manager: @llm_manager)
      @reranker = nil # Will initialize when needed
    end
    
    # Retrieve context without generating a response. Runs steps 1-5 of the
    # RAG pipeline (rewrite, retrieve, rerank, prepare, repack) and returns
    # the repacked context, sources, and confidence. Used by SearchDocs tool
    # so the Agent LLM can synthesize its own answer.
    def retrieve_context(user_query, top_k: 3, enable_rewriting: true, enable_reranking: false)
      rewritten = build_rewritten_query(user_query, enable_rewriting: enable_rewriting)
      candidates = retrieve_with_rrf(rewritten['sub_queries'], k: 20, verbose: false)

      return { context: "", sources: [], confidence: 0.0, clarified: user_query } if candidates.empty?

      if enable_reranking
        reranked = rerank_documents(query: user_query, documents: candidates, top_k: top_k * 2)
      else
        reranked = candidates
      end

      context_docs = prepare_context(reranked[0...top_k], rewritten['context_needed'])
      repacked = ContextRepacker.repack(context_docs, rewritten['clarified_intent'])
      confidence = calculate_confidence(context_docs)

      {
        context: repacked,
        sources: context_docs.map { |d|
          {
            source_file: d[:file_path] || d[:source_file] || d["file_path"],
            chunk_index: d[:chunk_index] || d["chunk_index"]
          }
        }.reject { |s| s[:source_file].nil? },
        confidence: confidence,
        clarified: rewritten['clarified_intent']
      }
    end

    def query(user_query, top_k: 3, verbose: false, enable_rewriting: true, enable_reranking: false)
      puts "Processing query: #{user_query}" if verbose
      
      # Step 1: Rewrite and analyze the query (if enabled)
      if enable_rewriting
        puts "\n#{'-'*60}" if verbose
        puts "STEP 1: Query Analysis & Rewriting" if verbose
        puts "-"*60 if verbose
        
        rewritten = @rewriter.rewrite(user_query)

        # Always include the original query in sub-queries to ensure direct matches
        # are found regardless of how the rewriter reformulates
        sub_queries = rewritten['sub_queries'] || []
        unless sub_queries.include?(user_query)
          sub_queries.unshift(user_query)
        end
        rewritten['sub_queries'] = sub_queries

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
      else
        # Skip rewriting - use original query directly
        rewritten = {
          'clarified_intent' => user_query,
          'query_type' => 'direct',
          'context_needed' => 'general',
          'sub_queries' => [user_query],
          'key_terms' => []
        }
        
        if verbose
          puts "\n#{'-'*60}"
          puts "STEP 1: Query Analysis (Rewriting Disabled)"
          puts "-"*60
          puts "\nUsing original query directly"
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
      
      if enable_reranking
        reranked = rerank_documents(
          query: user_query,
          documents: candidates,
          top_k: top_k * 2
        )
      else
        # Use retrieval order (RRF scores) directly — often more reliable than
        # small cross-encoder rerankers on domain-specific corpora
        reranked = candidates
      end

      if verbose && reranked.any?
        puts "\nTop #{enable_reranking ? 'Reranked' : 'Retrieved'} Documents:"
        reranked[0..2].each_with_index do |doc, idx|
          full_text = (doc[:chunk_text] || doc[:text] || "").gsub(/\s+/, ' ')
          puts "  #{idx + 1}. [#{File.basename(doc[:file_path] || 'unknown')}]"
          puts "     Score: #{doc[:score]&.round(4) if doc[:score]}"
          puts "     Distance: #{doc[:distance]&.round(4) if doc[:distance]}"
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
            source_file: d[:file_path] || d[:source_file] || d["file_path"],
            chunk_index: d[:chunk_index] || d["chunk_index"]
          }
        }.reject { |s| s[:source_file].nil? },
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
          puts "  Vector search: #{vector_results.length} matches"
          if vector_results.any?
            best = vector_results.first
            puts "  Best vector match: [#{File.basename(best[:file_path] || 'unknown')}] (distance: #{best[:distance]&.round(3)})"
          end
        end

        # Add query index for RRF
        vector_results.each do |result|
          result[:query_idx] = idx
          result[:retrieval_method] = :vector
        end

        all_results.concat(vector_results)

        # Full-text search for keyword matching (hybrid search)
        begin
          fts_results = @database.full_text_search(query, limit: k)
          if verbose && fts_results.any?
            puts "  FTS: #{fts_results.length} matches"
            best_fts = fts_results.first
            puts "  Best FTS match: [#{File.basename(best_fts[:file_path] || 'unknown')}]"
          end

          fts_results.each_with_index do |result, rank|
            # Synthesize a distance from FTS rank (lower rank = better match)
            result[:distance] = 0.1 + (rank * 0.05)
            result[:query_idx] = idx
            result[:retrieval_method] = :fts
          end

          all_results.concat(fts_results)
        rescue => e
          puts "  FTS unavailable: #{e.message}" if verbose
        end
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
        if doc_scores[doc_id]
          # Prefer the document with more complete metadata
          existing = doc_scores[doc_id][:document]
          if result[:file_path] && !existing[:file_path]
            doc_scores[doc_id][:document] = result
          end
        else
          doc_scores[doc_id] = {
            score: 0.0,
            document: result
          }
        end
        
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
      # Deduplicate documents based on chunk_text before reranking
      seen_texts = Set.new
      unique_docs = []
      
      documents.each do |doc|
        text = doc[:chunk_text] || doc[:text] || ""
        text_hash = Digest::SHA256.hexdigest(text)
        
        unless seen_texts.include?(text_hash)
          seen_texts.add(text_hash)
          unique_docs << doc
        end
      end
      
      if documents.length > unique_docs.length && @verbose
        puts "  Deduplicated: #{documents.length} -> #{unique_docs.length} documents"
      end
      
      # Initialize reranker if not already done
      @reranker ||= Candle::Reranker.from_pretrained(
        Config.instance.reranker_model
      )
      
      # Prepare document texts - use chunk_text field
      texts = unique_docs.map { |doc| doc[:chunk_text] || doc[:text] || "" }
      
      # Rerank - use raw logits (no sigmoid) for better score separation
      reranked = @reranker.rerank(query, texts, apply_sigmoid: false)
      
      # Map back to original documents with scores
      reranked.map do |result|
        doc_idx = result[:doc_id]
        unique_docs[doc_idx].merge(score: result[:score])
      end.sort_by { |doc| -doc[:score] }.first(top_k)
    rescue => e
      puts "Warning: Reranking failed (#{e.message}), using original order"
      unique_docs.first(top_k)
    end
    
    def prepare_context(documents, context_needed)
      # For now, just return the documents
      # In the future, we could fetch neighboring chunks for more context
      context_size = case context_needed
                     when "extensive" then 5
                     when "moderate" then 4
                     else 3
                     end
      
      documents.first(context_size)
    end
    
    def generate_response(query:, repacked_context:, query_type:)
      # Create a fresh chat for each query to avoid conversation history bleed
      chat = Config.instance.create_chat
      chat.with_instructions(
        "You are a helpful assistant. Answer questions based ONLY on the provided context. " \
        "If the answer is not in the context, say \"I don't have enough information to answer that question.\" " \
        "Be concise and direct. /no_think"
      )

      prompt = "Context:\n#{repacked_context}\n\nQuestion: #{query}"
      response = chat.ask(prompt).content
      # Strip <think>...</think> blocks that some models (e.g. Qwen3) include
      strip_think_tags(response)
    rescue => e
      # Fallback to returning the repacked context
      puts "Warning: LLM generation failed (#{e.message})"
      "Based on the retrieved information:\n\n#{repacked_context[0..500]}..."
    end
    
    def strip_think_tags(text)
      return text unless text
      text.gsub(/<think>.*?<\/think>/m, '').strip
    end

    def build_rewritten_query(user_query, enable_rewriting: true)
      if enable_rewriting
        rewritten = @rewriter.rewrite(user_query)
        sub_queries = rewritten['sub_queries'] || []
        unless sub_queries.include?(user_query)
          sub_queries.unshift(user_query)
        end
        rewritten['sub_queries'] = sub_queries
        rewritten
      else
        {
          'clarified_intent' => user_query,
          'query_type' => 'direct',
          'context_needed' => 'general',
          'sub_queries' => [user_query],
          'key_terms' => []
        }
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
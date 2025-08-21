module Ragnar
  class ContextRepacker
    # Repack retrieved documents into optimized context for LLM
    # This reduces redundancy and organizes information better
    def self.repack(documents, query, max_tokens: 2000)
      return "" if documents.empty?
      
      # Group documents by source file
      grouped = documents.group_by { |doc| doc[:file_path] || doc[:source_file] || "unknown" }
      
      # Build repacked context
      context_parts = []
      
      grouped.each do |source, docs|
        # Combine chunks from the same source
        combined_text = docs.map { |d| d[:chunk_text] || d[:text] || "" }
                            .reject(&:empty?)
                            .join(" ... ")
        
        # Remove excessive whitespace and clean up
        combined_text = clean_text(combined_text)
        
        # Add source header
        context_parts << "Source: #{File.basename(source)}\n#{combined_text}"
      end
      
      # Join all parts with clear separation
      full_context = context_parts.join("\n\n---\n\n")
      
      # Trim to max tokens (rough approximation: ~4 chars per token)
      max_chars = max_tokens * 4
      if full_context.length > max_chars
        full_context = trim_to_relevant(full_context, query, max_chars)
      end
      
      full_context
    end
    
    # Create a summary-focused repack for better coherence
    def self.repack_with_summary(documents, query, llm: nil)
      return "" if documents.empty?
      
      # First do basic repacking
      basic_context = repack(documents, query)
      
      # If we have an LLM, try to create a summary
      if llm
        begin
          summary_prompt = <<~PROMPT
            <|system|>
            You are a helpful assistant. Summarize the following information relevant to the query.
            Focus on the most important points. Be concise.
            </s>
            <|user|>
            Query: #{query}
            
            Information:
            #{basic_context[0..1500]}
            
            Provide a brief summary of the key information related to the query.
            </s>
            <|assistant|>
          PROMPT
          
          summary = llm.generate(summary_prompt)
          
          # Combine summary with original context
          <<~CONTEXT
            Summary: #{summary}
            
            Detailed Information:
            #{basic_context}
          CONTEXT
        rescue => e
          puts "Warning: Summary generation failed: #{e.message}"
          basic_context
        end
      else
        basic_context
      end
    end
    
    private
    
    def self.clean_text(text)
      text
        .gsub(/\s+/, ' ')           # Normalize whitespace
        .gsub(/\n{3,}/, "\n\n")     # Remove excessive newlines
        .gsub(/\.{4,}/, '...')      # Normalize ellipsis
        .strip
    end
    
    def self.trim_to_relevant(text, query, max_chars)
      # Try to keep the most relevant parts based on query terms
      query_terms = query.downcase.split(/\W+/).reject { |w| w.length < 3 }
      
      # Score each sentence by relevance
      sentences = text.split(/(?<=[.!?])\s+/)
      scored_sentences = sentences.map do |sentence|
        score = query_terms.sum { |term| sentence.downcase.include?(term) ? 1 : 0 }
        { sentence: sentence, score: score }
      end
      
      # Sort by score and reconstruct
      scored_sentences.sort_by! { |s| -s[:score] }
      
      result = []
      current_length = 0
      
      scored_sentences.each do |item|
        sentence_length = item[:sentence].length
        break if current_length + sentence_length > max_chars
        
        result << item[:sentence]
        current_length += sentence_length
      end
      
      result.join(" ")
    end
  end
end
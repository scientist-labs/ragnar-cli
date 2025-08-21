# Separate strategy classes for different labeling approaches
module Ragnar
  module TopicModeling
    module LabelingStrategies
      
      # Base strategy class
      class Base
        def generate_label(topic:, terms:, documents:)
          raise NotImplementedError, "Subclasses must implement generate_label"
        end
        
        protected
        
        def select_representative_docs(documents, k: 3)
          return documents if documents.length <= k
          
          # For now, just take first k
          # Could be improved to select most central docs
          documents.first(k)
        end
        
        def capitalize_phrase(phrase)
          phrase.split(/[\s_-]/).map(&:capitalize).join(' ')
        end
      end
      
      # Fast term-based labeling using c-TF-IDF terms
      class TermBased < Base
        def generate_label(topic:, terms:, documents:)
          return { label: "Empty Topic", description: "No terms found" } if terms.empty?
          
          # Take top distinctive terms
          label_terms = terms.first(3).select { |t| t.length > 3 }
          
          label = if label_terms.length >= 2
            "#{capitalize_phrase(label_terms[0])} & #{capitalize_phrase(label_terms[1])}"
          else
            capitalize_phrase(label_terms.first || terms.first)
          end
          
          {
            label: label,
            description: "Documents about #{terms.first(5).join(', ')}",
            method: :term_based,
            confidence: calculate_confidence(terms)
          }
        end
        
        private
        
        def calculate_confidence(terms)
          # Simple heuristic: more distinctive terms = higher confidence
          return 0.0 if terms.empty?
          
          # Assume terms come with scores if available
          if terms.is_a?(Array) && terms.first.is_a?(Array)
            # Terms are [word, score] pairs
            avg_score = terms.first(5).map(&:last).sum / 5.0
            [avg_score, 1.0].min
          else
            # Just have terms, use count as proxy
            [terms.length / 20.0, 1.0].min
          end
        end
      end
      
      # Quality LLM-based labeling
      class LLMBased < Base
        def initialize(llm_client: nil)
          @llm_client = llm_client
        end
        
        def generate_label(topic:, terms:, documents:)
          unless llm_available?
            # Fallback to term-based if LLM not available
            return TermBased.new.generate_label(topic: topic, terms: terms, documents: documents)
          end
          
          # Select best documents to send to LLM
          sample_docs = select_representative_docs(documents, k: 3)
          
          # Generate comprehensive analysis
          response = analyze_with_llm(sample_docs, terms)
          
          {
            label: response[:label],
            description: response[:description],
            themes: response[:themes],
            method: :llm_based,
            confidence: response[:confidence] || 0.8
          }
        rescue => e
          # Fallback on error
          puts "LLM labeling failed: #{e.message}" if ENV['DEBUG']
          TermBased.new.generate_label(topic: topic, terms: terms, documents: documents)
        end
        
        private
        
        def llm_available?
          return true if @llm_client
          
          # Try to create LLM adapter
          begin
            require_relative 'llm_adapter'
            @llm_client = LLMAdapter.create(type: :auto)
            @llm_client && @llm_client.available?
          rescue LoadError, StandardError => e
            puts "LLM not available: #{e.message}" if ENV['DEBUG']
            false
          end
        end
        
        def analyze_with_llm(documents, terms)
          prompt = build_analysis_prompt(documents, terms)
          
          response = @llm_client.generate(
            prompt: prompt,
            max_tokens: 150,
            temperature: 0.3,
            response_format: { type: "json_object" }
          )
          
          # Parse JSON response
          result = JSON.parse(response, symbolize_names: true)
          
          # Validate and clean
          {
            label: clean_label(result[:label]),
            description: result[:description] || "Topic about #{result[:label]}",
            themes: result[:themes] || [],
            confidence: result[:confidence] || 0.8
          }
        end
        
        def build_analysis_prompt(documents, terms)
          doc_samples = documents.map.with_index do |doc, i|
            preview = doc.length > 300 ? "#{doc[0..300]}..." : doc
            "Document #{i + 1}:\n#{preview}"
          end.join("\n\n")
          
          <<~PROMPT
            Analyze this cluster of related documents and provide a structured summary.
            
            Distinctive terms found: #{terms.first(10).join(', ')}
            
            Sample documents:
            #{doc_samples}
            
            Provide a JSON response with:
            {
              "label": "A 2-4 word topic label",
              "description": "One sentence describing what connects these documents",
              "themes": ["theme1", "theme2", "theme3"],
              "confidence": 0.0-1.0 score of how coherent this topic is
            }
            
            Focus on what meaningfully connects these documents, not just common words.
          PROMPT
        end
        
        def clean_label(label)
          return "Unknown Topic" unless label
          
          # Remove quotes, trim, limit length
          cleaned = label.to_s.strip.gsub(/^["']|["']$/, '')
          cleaned = cleaned.split("\n").first if cleaned.include?("\n")
          
          # Limit to reasonable length
          if cleaned.length > 50
            cleaned[0..47] + "..."
          else
            cleaned
          end
        end
      end
      
      # Hybrid approach - uses terms to guide LLM for efficiency
      class Hybrid < Base
        def initialize(llm_client: nil)
          @llm_client = llm_client
          @term_strategy = TermBased.new
        end
        
        def generate_label(topic:, terms:, documents:)
          # Start with term-based analysis
          term_result = @term_strategy.generate_label(
            topic: topic, 
            terms: terms, 
            documents: documents
          )
          
          # If no LLM available, return term-based result
          unless llm_available?
            return term_result.merge(method: :hybrid_fallback)
          end
          
          # Enhance with focused LLM call
          enhanced = enhance_with_llm(term_result, terms, documents)
          
          {
            label: enhanced[:label] || term_result[:label],
            description: enhanced[:description] || term_result[:description],
            method: :hybrid,
            confidence: (term_result[:confidence] + (enhanced[:confidence] || 0.5)) / 2,
            term_label: term_result[:label],  # Keep original for comparison
            themes: enhanced[:themes]
          }
        rescue => e
          # Fallback to term-based
          puts "Hybrid enhancement failed: #{e.message}" if ENV['DEBUG']
          term_result.merge(method: :hybrid_fallback)
        end
        
        private
        
        def llm_available?
          return true if @llm_client
          
          begin
            require_relative 'llm_adapter'
            @llm_client = LLMAdapter.create(type: :auto)
            @llm_client && @llm_client.available?
          rescue LoadError, StandardError => e
            puts "LLM not available for hybrid: #{e.message}" if ENV['DEBUG']
            false
          end
        end
        
        def enhance_with_llm(term_result, terms, documents)
          # Lighter-weight prompt using term analysis as starting point
          prompt = build_enhancement_prompt(term_result[:label], terms, documents.first)
          
          response = @llm_client.generate(
            prompt: prompt,
            max_tokens: 100,
            temperature: 0.3
          )
          
          # Parse response (simpler format for speed)
          parse_enhancement_response(response)
        end
        
        def build_enhancement_prompt(term_label, terms, sample_doc)
          doc_preview = sample_doc.length > 200 ? "#{sample_doc[0..200]}..." : sample_doc
          
          <<~PROMPT
            Current topic label based on terms: "#{term_label}"
            Key terms: #{terms.first(8).join(', ')}
            
            Sample document:
            #{doc_preview}
            
            Provide a better topic label if possible (2-4 words), or confirm the current one.
            Also provide a one-sentence description.
            
            Format:
            Label: [your label]
            Description: [one sentence]
            Themes: [comma-separated list]
          PROMPT
        end
        
        def parse_enhancement_response(response)
          result = {}
          
          # Simple line-based parsing
          response.lines.each do |line|
            if line.start_with?("Label:")
              result[:label] = line.sub("Label:", "").strip
            elsif line.start_with?("Description:")
              result[:description] = line.sub("Description:", "").strip
            elsif line.start_with?("Themes:")
              themes_str = line.sub("Themes:", "").strip
              result[:themes] = themes_str.split(",").map(&:strip)
            end
          end
          
          result[:confidence] = result[:label] ? 0.7 : 0.3
          result
        end
      end
      
      # Factory method to get appropriate strategy
      def self.create(method, llm_client: nil)
        case method.to_sym
        when :fast, :term_based, :terms
          TermBased.new
        when :quality, :llm_based, :llm
          LLMBased.new(llm_client: llm_client)
        when :hybrid, :auto, :smart
          Hybrid.new(llm_client: llm_client)
        else
          # Default to hybrid
          Hybrid.new(llm_client: llm_client)
        end
      end
    end
  end
end
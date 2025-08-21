require_relative 'labeling_strategies'

module Ragnar
  module TopicModeling
    class TopicLabeler
      attr_reader :strategy
      
      def initialize(method: :hybrid, llm_client: nil)
        @method = method
        @llm_client = llm_client
        @strategy = LabelingStrategies.create(method, llm_client: llm_client)
      end
      
      # Generate a human-readable label for a topic
      # Returns a hash with label, description, and metadata
      def generate_label(topic: nil, terms:, documents: [], method: nil)
        # Allow method override per call
        if method && method != @method
          strategy = LabelingStrategies.create(method, llm_client: @llm_client)
        else
          strategy = @strategy
        end
        
        # Generate label using selected strategy
        result = strategy.generate_label(
          topic: topic,
          terms: terms,
          documents: documents
        )
        
        # Ensure we always return a consistent structure
        normalize_result(result)
      end
      
      # Convenience method for simple label string
      def generate_simple_label(terms:, documents: [], method: nil)
        result = generate_label(terms: terms, documents: documents, method: method)
        result[:label]
      end
      
      # Change strategy at runtime
      def set_strategy(method)
        @method = method
        @strategy = LabelingStrategies.create(method, llm_client: @llm_client)
      end
      
      private
      
      def normalize_result(result)
        {
          label: result[:label] || "Unknown Topic",
          description: result[:description] || nil,
          method: result[:method] || @method,
          confidence: result[:confidence] || 0.5,
          themes: result[:themes] || [],
          metadata: result.reject { |k, _| [:label, :description, :method, :confidence, :themes].include?(k) }
        }
      end
    end
  end
end
# Main entry point for topic modeling functionality
# Designed for future extraction into a separate gem

require_relative 'topic_modeling/topic'
require_relative 'topic_modeling/term_extractor'
require_relative 'topic_modeling/metrics'
require_relative 'topic_modeling/topic_labeler'
require_relative 'topic_modeling/engine'

module Ragnar
  module TopicModeling
    
    # Convenience method to create a new topic modeling engine
    def self.new(**options)
      Engine.new(**options)
    end
    
    # Extract topics from embeddings and documents (simple interface)
    def self.extract(embeddings:, documents:, **options)
      engine = Engine.new(**options)
      engine.fit(embeddings: embeddings, documents: documents)
    end
  end
end
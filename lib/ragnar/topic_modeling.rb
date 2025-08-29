# frozen_string_literal: true

# Topic modeling wrapper that delegates to the Topical gem
# This maintains backward compatibility while using the extracted library

require 'topical'

module Ragnar
  module TopicModeling
    # Re-export Topical classes for backward compatibility
    Topic = Topical::Topic
    Engine = Topical::Engine
    
    # Re-export metrics module
    Metrics = Topical::Metrics
    
    # Convenience method to create a new topic modeling engine
    def self.new(**options)
      Topical::Engine.new(**options)
    end
    
    # Extract topics from embeddings and documents (simple interface)
    def self.extract(embeddings:, documents:, **options)
      Topical.extract(embeddings: embeddings, documents: documents, **options)
    end
  end
end
module Ragnar
  module TopicModeling
    class Topic
      attr_reader :id, :document_indices, :documents, :embeddings, :metadata
      attr_accessor :terms, :label
      
      def initialize(id:, document_indices:, documents:, embeddings:, metadata: nil)
        @id = id
        @document_indices = document_indices
        @documents = documents
        @embeddings = embeddings
        @metadata = metadata || []
        @terms = []
        @label = nil
      end
      
      def size
        @documents.length
      end
      
      def centroid
        @centroid ||= compute_centroid
      end
      
      def representative_docs(k: 3)
        return @documents if @documents.length <= k
        
        # Find documents closest to centroid
        distances = @embeddings.map do |embedding|
          distance_to_centroid(embedding)
        end
        
        # Get indices of k smallest distances
        top_indices = distances.each_with_index.sort_by(&:first).first(k).map(&:last)
        top_indices.map { |i| @documents[i] }
      end
      
      def coherence
        @coherence ||= Metrics.compute_coherence(@terms, @documents)
      end
      
      def distinctiveness(other_topics)
        @distinctiveness ||= Metrics.compute_distinctiveness(self, other_topics)
      end
      
      def set_terms(terms)
        @terms = terms
        @centroid = nil  # Reset centroid cache
      end
      
      def set_label(label)
        @label = label
      end
      
      def summary
        {
          id: @id,
          label: @label || "Topic #{@id}",
          size: size,
          terms: @terms.first(10),
          coherence: coherence.round(3),
          representative_docs: representative_docs(k: 2).map { |d| d[0..100] + "..." }
        }
      end
      
      def to_h
        {
          id: @id,
          label: @label,
          document_indices: @document_indices,
          terms: @terms,
          centroid: centroid,
          size: size,
          coherence: coherence
        }
      end
      
      def self.from_h(hash)
        topic = new(
          id: hash[:id],
          document_indices: hash[:document_indices],
          documents: [],  # Would need to be reconstructed
          embeddings: [],  # Would need to be reconstructed
          metadata: []
        )
        topic.set_label(hash[:label])
        topic.set_terms(hash[:terms])
        topic
      end
      
      private
      
      def compute_centroid
        return [] if @embeddings.empty?
        
        # Compute mean of all embeddings
        dim = @embeddings.first.length
        centroid = Array.new(dim, 0.0)
        
        @embeddings.each do |embedding|
          embedding.each_with_index do |val, idx|
            centroid[idx] += val
          end
        end
        
        centroid.map { |val| val / @embeddings.length }
      end
      
      def distance_to_centroid(embedding)
        # Euclidean distance
        Math.sqrt(
          embedding.zip(centroid).map { |a, b| (a - b) ** 2 }.sum
        )
      end
    end
  end
end
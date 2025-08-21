require 'clusterkit'

module Ragnar
  class UmapTransformService
    include Singleton
    
    def initialize
      @umap_model = nil
      @model_path = "umap_model.bin"
    end
    
    # Transform a query embedding to reduced space using saved UMAP model
    def transform_query(query_embedding, model_path = nil)
      # Use the real UMAP model's transform capability
      model_path ||= @model_path
      
      # Load the model if not already loaded
      load_model(model_path) unless @umap_model
      
      # Transform the query embedding using the trained UMAP model
      # The transform method expects a 2D array (even for a single embedding)
      result = @umap_model.transform([query_embedding])
      
      # Return the first (and only) transformed embedding
      result.first
    rescue => e
      # Fall back to k-NN approximation if model loading fails
      puts "Warning: Could not use UMAP model for transform: #{e.message}"
      puts "Falling back to k-NN approximation..."
      knn_approximate_transform(query_embedding)
    end
    
    # Check if we can do transforms
    def model_available?(model_path = nil)
      model_path ||= @model_path
      
      # First check if the actual UMAP model file exists
      if File.exist?(model_path)
        return true
      end
      
      # Fallback: check if the database has reduced embeddings for k-NN approximation
      database = Database.new("./rag_database")
      stats = database.get_stats
      stats[:with_reduced_embeddings] > 0
    end
    
    private
    
    def load_model(model_path)
      unless File.exist?(model_path)
        raise "UMAP model not found at #{model_path}. Please train a model first."
      end
      
      @umap_model = ClusterKit::Dimensionality::UMAP.load_model(model_path)
      puts "UMAP model loaded for query transformation"
    end
    
    def knn_approximate_transform(query_embedding)
      # Fallback k-NN approximation method
      # Get database stats to know dimensions
      database = Database.new("./rag_database")
      stats = database.get_stats
      
      # If we don't have reduced embeddings, we can't transform
      if stats[:with_reduced_embeddings] == 0
        raise "No reduced embeddings available in database"
      end
      
      # Get all documents with their embeddings
      all_docs = database.get_embeddings
      
      # Find k nearest neighbors in full embedding space
      k = 5
      neighbors = []
      
      all_docs.each_with_index do |doc, idx|
        next unless doc[:embedding] && doc[:reduced_embedding]
        
        distance = euclidean_distance(query_embedding, doc[:embedding])
        neighbors << { idx: idx, distance: distance, reduced: doc[:reduced_embedding] }
      end
      
      # Sort by distance and take k nearest
      neighbors.sort_by! { |n| n[:distance] }
      k_nearest = neighbors.first(k)
      
      # Average the reduced embeddings of k nearest neighbors
      # This is a simple approximation of the transform
      if k_nearest.empty?
        raise "No neighbors found for transform"
      end
      
      reduced_dims = k_nearest.first[:reduced].size
      averaged = Array.new(reduced_dims, 0.0)
      
      # Weighted average based on inverse distance
      total_weight = 0.0
      k_nearest.each do |neighbor|
        # Use inverse distance as weight (closer = higher weight)
        weight = 1.0 / (neighbor[:distance] + 0.001) # Add small epsilon to avoid division by zero
        total_weight += weight
        
        neighbor[:reduced].each_with_index do |val, idx|
          averaged[idx] += val * weight
        end
      end
      
      # Normalize by total weight
      averaged.map { |val| val / total_weight }
    end
    
    def euclidean_distance(vec1, vec2)
      return Float::INFINITY if vec1.size != vec2.size
      
      sum = 0.0
      vec1.each_with_index do |val, idx|
        diff = val - vec2[idx]
        sum += diff * diff
      end
      Math.sqrt(sum)
    end
  end
end
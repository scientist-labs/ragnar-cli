require 'json'

module Ragnar
  class UmapProcessor
    attr_reader :database, :model_path
    
    def initialize(db_path: Ragnar::DEFAULT_DB_PATH, model_path: "umap_model.bin")
      @database = Database.new(db_path)
      @model_path = model_path
      @umap_model = nil
    end
    
    def train(n_components: Ragnar::DEFAULT_REDUCED_DIMENSIONS, n_neighbors: 15, min_dist: 0.1)
      puts "Loading embeddings from database..."
      
      # Get all embeddings
      docs = @database.get_embeddings
      
      if docs.empty?
        raise "No embeddings found in database. Please index some documents first."
      end
      
      embeddings = docs.map { |d| d[:embedding] }.compact
      
      if embeddings.empty?
        raise "No valid embeddings found in database."
      end
      
      puts "Found #{embeddings.size} embeddings"
      
      # Adjust parameters based on the number of samples
      # UMAP requires n_neighbors < n_samples
      # Also, n_components should be less than n_samples for stability
      n_samples = embeddings.size
      
      if n_neighbors >= n_samples
        n_neighbors = [3, (n_samples - 1) / 2].max.to_i
        puts "  Adjusted n_neighbors to #{n_neighbors} (was #{15}, but only have #{n_samples} samples)"
      end
      
      if n_components >= n_samples
        n_components = [2, n_samples - 1].min
        puts "  Adjusted n_components to #{n_components} (was #{50}, but only have #{n_samples} samples)"
      end
      
      # Warn if we have very few samples
      if n_samples < 100
        puts "\n  ⚠️  Warning: UMAP works best with at least 100 samples."
        puts "     You currently have #{n_samples} samples."
        puts "     Consider indexing more documents for better results."
      end
      
      # Convert to matrix format for ClusterKit
      # ClusterKit expects a 2D array or Numo::NArray
      embedding_matrix = embeddings
      original_dims = embeddings.first.size
      
      puts "\nTraining UMAP model..."
      puts "  Original dimensions: #{original_dims}"
      puts "  Target dimensions: #{n_components}"
      puts "  Neighbors: #{n_neighbors}"
      puts "  Min distance: #{min_dist}"
      
      # Use the simple ClusterKit.umap method
      progressbar = TTY::ProgressBar.new(
        "Training UMAP [:bar] :percent",
        total: 100,
        bar_format: :block,
        width: 30
      )
      
      # Start progress in background (ClusterKit doesn't provide callbacks)
      progress_thread = Thread.new do
        100.times do
          sleep(0.05)
          progressbar.advance
          break if @training_complete
        end
      end
      
      # Perform the actual training using the class-based API
      @umap_instance = ClusterKit::Dimensionality::UMAP.new(
        n_components: n_components,
        n_neighbors: n_neighbors
      )
      
      @reduced_embeddings = @umap_instance.fit_transform(embedding_matrix)
      
      @training_complete = true
      progress_thread.join
      progressbar.finish
      
      # Store the parameters for saving
      @model_params = {
        n_components: n_components,
        n_neighbors: n_neighbors,
        min_dist: min_dist
      }
      
      # Save the model
      save_model
      
      {
        embeddings_count: embeddings.size,
        original_dims: original_dims,
        reduced_dims: n_components
      }
    end
    
    def apply(batch_size: 100)
      # Load the trained UMAP model (reduced embeddings)
      reduced_embeddings = load_model
      
      puts "Applying saved UMAP embeddings to database..."
      
      # Get all embeddings from database
      all_docs = @database.get_embeddings
      
      if all_docs.empty?
        puts "No embeddings found in database."
        return {
          processed: 0,
          skipped: 0,
          errors: 0
        }
      end
      
      puts "Found #{all_docs.size} documents in database"
      puts "Loaded #{reduced_embeddings.size} reduced embeddings from model"
      
      if all_docs.size != reduced_embeddings.size
        puts "⚠️  Warning: Mismatch between database documents (#{all_docs.size}) and model embeddings (#{reduced_embeddings.size})"
        puts "   This suggests the model was trained on a different dataset."
        puts "   Please retrain the UMAP model after indexing all your documents."
        return {
          processed: 0,
          skipped: 0,
          errors: 1
        }
      end
      
      # Prepare updates - match document IDs to reduced embeddings
      updates = all_docs.each_with_index.map do |doc, idx|
        {
          id: doc[:id],
          reduced_embedding: reduced_embeddings[idx]
        }
      end
      
      puts "Updating database with reduced embeddings..."
      @database.update_reduced_embeddings(updates)
      
      {
        processed: updates.size,
        skipped: 0,
        errors: 0
      }
    end
    
    private
    
    def process_batch(docs)
      # Extract embeddings
      embeddings = docs.map { |d| d[:embedding] }
      
      # Transform using UMAP
      # The transform method returns a 2D array where each row is a reduced embedding
      reduced = @umap_model.transform(embeddings)
      
      # Prepare updates
      updates = docs.each_with_index.map do |doc, idx|
        {
          id: doc[:id],
          reduced_embedding: reduced[idx]
        }
      end
      
      # Update database
      @database.update_reduced_embeddings(updates)
    end
    
    def save_model
      return unless @umap_instance && @reduced_embeddings
      
      # Save the trained UMAP model for transforming new queries
      @umap_instance.save_model(@model_path)
      puts "UMAP model saved to: #{@model_path}"
      
      # Also cache the reduced embeddings separately for the apply method
      embeddings_path = @model_path.sub(/\.bin$/, '_embeddings.json')
      ClusterKit::Dimensionality::UMAP.save_data(@reduced_embeddings, embeddings_path)
      puts "Reduced embeddings cached to: #{embeddings_path}"
    end
    
    def load_model
      return @reduced_embeddings if @reduced_embeddings
      
      # For the apply method, we need the pre-computed embeddings
      embeddings_path = @model_path.sub(/\.bin$/, '_embeddings.json')
      unless File.exist?(embeddings_path)
        raise "Cached embeddings not found at #{embeddings_path}. Please train a model first."
      end
      
      @reduced_embeddings = ClusterKit::Dimensionality::UMAP.load_data(embeddings_path)
      puts "Cached embeddings loaded from: #{embeddings_path}"
      @reduced_embeddings
    end
    
    def load_umap_model
      # Load the actual UMAP model for transforming new data
      unless File.exist?(@model_path)
        raise "UMAP model not found at #{@model_path}. Please train a model first."
      end
      
      @umap_instance ||= ClusterKit::Dimensionality::UMAP.load_model(@model_path)
      puts "UMAP model loaded from: #{@model_path}"
      @umap_instance
    end
    
    def self.optimal_dimensions(original_dims, target_ratio: 0.1)
      # Suggest optimal number of dimensions for reduction
      # Common heuristic: reduce to 10% of original dimensions
      # but keep at least 50 dimensions for good quality
      suggested = (original_dims * target_ratio).to_i
      [suggested, 50].max
    end
  end
end
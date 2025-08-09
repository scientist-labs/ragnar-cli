module RubyRag
  class UmapProcessor
    attr_reader :database, :model_path
    
    def initialize(db_path: RubyRag::DEFAULT_DB_PATH, model_path: "umap_model.bin")
      @database = Database.new(db_path)
      @model_path = model_path
      @umap_model = nil
    end
    
    def train(n_components: 50, n_neighbors: 15, min_dist: 0.1)
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
      
      # Convert to matrix format for AnnEmbed
      # AnnEmbed expects a 2D array or Numo::NArray
      embedding_matrix = embeddings
      original_dims = embeddings.first.size
      
      puts "\nTraining UMAP model..."
      puts "  Original dimensions: #{original_dims}"
      puts "  Target dimensions: #{n_components}"
      puts "  Neighbors: #{n_neighbors}"
      puts "  Min distance: #{min_dist}"
      
      # Use the simple AnnEmbed.umap method
      progressbar = TTY::ProgressBar.new(
        "Training UMAP [:bar] :percent",
        total: 100,
        bar_format: :block,
        width: 30
      )
      
      # Start progress in background (AnnEmbed doesn't provide callbacks)
      progress_thread = Thread.new do
        100.times do
          sleep(0.05)
          progressbar.advance
          break if @training_complete
        end
      end
      
      # Perform the actual training using the simple API
      result = AnnEmbed.umap(
        embedding_matrix,
        n_components: n_components,
        n_neighbors: n_neighbors,
        min_dist: min_dist,
        spread: 1.0
      )
      
      @training_complete = true
      progress_thread.join
      progressbar.finish
      
      # Convert Numo array result to Ruby arrays for storage
      # result is a Numo::DFloat with shape [n_samples, n_components]
      @reduced_embeddings = result.to_a
      
      # Store the parameters for later use (since we can't save/load with simple API)
      @model_params = {
        n_components: n_components,
        n_neighbors: n_neighbors,
        min_dist: min_dist,
        training_data: embedding_matrix,
        reduced_embeddings: @reduced_embeddings
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
      unless File.exist?(@model_path)
        raise "UMAP model not found at #{@model_path}. Please train a model first."
      end
      
      # Load the model parameters
      load_model
      
      puts "Note: Using re-computation approach for UMAP transformation"
      puts "Loading embeddings from database..."
      
      # Get all embeddings
      all_docs = @database.get_embeddings
      
      if all_docs.empty?
        puts "No embeddings found in database."
        return {
          processed: 0,
          skipped: 0,
          errors: 0
        }
      end
      
      puts "Found #{all_docs.size} embeddings to process"
      
      # Extract all embeddings
      all_embeddings = all_docs.map { |d| d[:embedding] }
      
      # Re-run UMAP on all data with saved parameters
      # This is a limitation of the simple API - we can't incrementally transform
      puts "Applying UMAP to all embeddings..."
      result = AnnEmbed.umap(
        all_embeddings,
        n_components: @model_params[:n_components],
        n_neighbors: @model_params[:n_neighbors],
        min_dist: @model_params[:min_dist],
        spread: 1.0
      )
      
      # Convert Numo array to Ruby array
      reduced = result.to_a
      
      # Prepare updates
      updates = all_docs.each_with_index.map do |doc, idx|
        {
          id: doc[:id],
          reduced_embedding: reduced[idx]
        }
      end
      
      # Update database
      @database.update_reduced_embeddings(updates)
      
      {
        processed: all_docs.size,
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
      return unless @model_params
      
      # Save model parameters and training data to a file
      # Since AnnEmbed.umap doesn't support save/load, we store the parameters
      File.open(@model_path, 'wb') do |f|
        Marshal.dump(@model_params, f)
      end
      puts "Model parameters saved to: #{@model_path}"
    end
    
    def load_model
      return @model_params if @model_params
      
      # Load model parameters from file
      File.open(@model_path, 'rb') do |f|
        @model_params = Marshal.load(f)
      end
      @model_params
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
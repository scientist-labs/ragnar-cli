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
      
      # Convert to matrix format for Annembed
      embedding_matrix = embeddings
      original_dims = embeddings.first.size
      
      puts "Training UMAP model..."
      puts "  Original dimensions: #{original_dims}"
      puts "  Target dimensions: #{n_components}"
      puts "  Neighbors: #{n_neighbors}"
      puts "  Min distance: #{min_dist}"
      
      # Train UMAP using Annembed
      @umap_model = Annembed::Umap.new(
        n_components: n_components,
        n_neighbors: n_neighbors,
        min_dist: min_dist,
        metric: "euclidean",
        random_state: 42
      )
      
      # Fit the model
      progressbar = TTY::ProgressBar.new(
        "Training UMAP [:bar] :percent",
        total: 100,
        bar_format: :block,
        width: 30
      )
      
      # Simulate progress since Annembed doesn't provide callbacks
      Thread.new do
        100.times do
          sleep(0.1)
          progressbar.advance
        end
      end
      
      @umap_model.fit(embedding_matrix)
      progressbar.finish
      
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
      
      # Load the model
      load_model
      
      puts "Loading embeddings from database..."
      
      # Get embeddings that don't have reduced versions yet
      all_docs = @database.get_embeddings
      
      docs_to_process = all_docs.select do |doc|
        doc[:embedding] && (doc[:reduced_embedding].nil? || doc[:reduced_embedding].empty?)
      end
      
      if docs_to_process.empty?
        puts "All embeddings already have reduced versions."
        return {
          processed: 0,
          skipped: all_docs.size,
          errors: 0
        }
      end
      
      puts "Found #{docs_to_process.size} embeddings to process"
      
      stats = {
        processed: 0,
        skipped: all_docs.size - docs_to_process.size,
        errors: 0
      }
      
      # Process in batches
      progressbar = TTY::ProgressBar.new(
        "Applying UMAP [:bar] :percent :current/:total",
        total: docs_to_process.size,
        bar_format: :block,
        width: 30
      )
      
      docs_to_process.each_slice(batch_size) do |batch|
        begin
          process_batch(batch)
          stats[:processed] += batch.size
        rescue => e
          puts "\nError processing batch: #{e.message}"
          stats[:errors] += batch.size
        end
        
        progressbar.advance(batch.size)
      end
      
      progressbar.finish
      stats
    end
    
    private
    
    def process_batch(docs)
      # Extract embeddings
      embeddings = docs.map { |d| d[:embedding] }
      
      # Transform using UMAP
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
      return unless @umap_model
      
      # Save UMAP model using Annembed's save functionality
      @umap_model.save(@model_path)
      puts "Model saved to: #{@model_path}"
    end
    
    def load_model
      return @umap_model if @umap_model
      
      # Load UMAP model using Annembed's load functionality
      @umap_model = Annembed::Umap.load(@model_path)
      @umap_model
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
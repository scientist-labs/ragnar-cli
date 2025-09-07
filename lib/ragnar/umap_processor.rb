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
      
      # Validate embeddings
      embedding_dims = embeddings.map(&:size).uniq
      if embedding_dims.size > 1
        puts "  ⚠️  Warning: Inconsistent embedding dimensions found: #{embedding_dims.inspect}"
        puts "     This may cause errors during UMAP training."
        # Filter to only embeddings with the most common dimension
        most_common_dim = embedding_dims.max_by { |dim| embeddings.count { |e| e.size == dim } }
        embeddings = embeddings.select { |e| e.size == most_common_dim }
        puts "     Using only embeddings with #{most_common_dim} dimensions (#{embeddings.size} embeddings)"
      end
      
      # Check for nil or invalid values
      invalid_count = 0
      nan_count = 0
      inf_count = 0
      
      valid_embeddings = embeddings.select do |embedding|
        if !embedding.is_a?(Array)
          invalid_count += 1
          false
        elsif embedding.any? { |v| !v.is_a?(Numeric) }
          invalid_count += 1
          false
        elsif embedding.any?(&:nan?)
          nan_count += 1
          false
        elsif embedding.any? { |v| !v.finite? }
          inf_count += 1
          false
        else
          true
        end
      end
      
      if valid_embeddings.size < embeddings.size
        puts "\n  ⚠️  Data quality issues detected:"
        puts "     • Invalid embeddings: #{invalid_count}" if invalid_count > 0
        puts "     • Embeddings with NaN: #{nan_count}" if nan_count > 0
        puts "     • Embeddings with Infinity: #{inf_count}" if inf_count > 0
        puts "     • Total removed: #{embeddings.size - valid_embeddings.size}"
        puts "     • Remaining valid: #{valid_embeddings.size}"
        
        embeddings = valid_embeddings
      end
      
      if embeddings.empty?
        raise "No valid embeddings found after validation.\n\n" \
              "All embeddings contain invalid values (NaN, Infinity, or non-numeric).\n" \
              "This suggests a problem with the embedding model or indexing process.\n\n" \
              "Please try:\n" \
              "  1. Re-indexing your documents: ragnar index <path> --force\n" \
              "  2. Using a different embedding model\n" \
              "  3. Checking your document content for unusual characters"
      end
      
      if embeddings.size < 10
        raise "Too few valid embeddings (#{embeddings.size}) for UMAP training.\n\n" \
              "UMAP requires at least 10 samples to work effectively.\n" \
              "Please index more documents or check for data quality issues."
      end
      
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
      
      # Ensure n_components is reasonable
      if n_components >= original_dims
        puts "  ⚠️  Warning: n_components (#{n_components}) >= original dimensions (#{original_dims})"
        n_components = [original_dims / 2, 50].min
        puts "     Reducing n_components to #{n_components}"
      end
      
      # For very high dimensional data, be more conservative
      if original_dims > 500 && n_components > 50
        puts "  ⚠️  Note: High dimensional data (#{original_dims}D) being reduced to #{n_components}D"
        puts "     Consider using n_components <= 50 for stability"
      end
      
      puts "\nTraining UMAP model..."
      puts "  Original dimensions: #{original_dims}"
      puts "  Target dimensions: #{n_components}"
      puts "  Neighbors: #{n_neighbors}"
      puts "  Min distance: #{min_dist}"
      
      # Perform the actual training using the class-based API
      puts "  Training UMAP model (this may take a moment)..."
      
      begin
        @umap_instance = ClusterKit::Dimensionality::UMAP.new(
          n_components: n_components,
          n_neighbors: n_neighbors
        )
        
        @reduced_embeddings = @umap_instance.fit_transform(embedding_matrix)
        
        puts "  ✓ UMAP training complete"
      rescue => e
        # Provide helpful error message without exposing internal stack trace
        error_msg = "\n❌ UMAP training failed\n\n"
        
        if e.message.include?("index out of bounds")
          error_msg += "The UMAP algorithm encountered an index out of bounds error.\n\n"
          error_msg += "This typically happens when:\n"
          error_msg += "  • The embedding data contains invalid values (NaN, Infinity)\n"
          error_msg += "  • The parameters are incompatible with your data\n"
          error_msg += "  • There are duplicate or corrupted embeddings\n\n"
          error_msg += "Suggested solutions:\n"
          error_msg += "  1. Try with more conservative parameters:\n"
          error_msg += "     ragnar train-umap --n-components 10 --n-neighbors 5\n\n"
          error_msg += "  2. Re-index your documents to regenerate embeddings:\n"
          error_msg += "     ragnar index <path> --force\n\n"
          error_msg += "  3. Check your embedding model configuration\n\n"
          error_msg += "Current parameters:\n"
          error_msg += "  • n_components: #{n_components}\n"
          error_msg += "  • n_neighbors: #{n_neighbors}\n"
          error_msg += "  • embeddings: #{embeddings.size} samples\n"
          error_msg += "  • dimensions: #{original_dims}\n"
        else
          error_msg += "Error: #{e.message}\n\n"
          error_msg += "This may be due to incompatible parameters or data issues.\n"
          error_msg += "Try using more conservative parameters:\n"
          error_msg += "  ragnar train-umap --n-components 10 --n-neighbors 5\n"
        end
        
        raise RuntimeError, error_msg
      end
      
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
      # Load the trained UMAP model
      umap_model = load_umap_model
      
      puts "Applying UMAP transformation to database documents..."
      
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
      
      # Process in batches for memory efficiency
      processed_count = 0
      error_count = 0
      skipped_count = 0
      
      all_docs.each_slice(batch_size) do |batch|
        begin
          # Extract embeddings
          embeddings = batch.map { |d| d[:embedding] }
          
          # Validate embeddings
          valid_indices = []
          embeddings_to_transform = []
          
          embeddings.each_with_index do |emb, idx|
            if emb.nil? || !emb.is_a?(Array) || emb.empty?
              skipped_count += 1
              next
            end
            
            if emb.any? { |v| !v.is_a?(Numeric) || v.nan? || !v.finite? }
              skipped_count += 1
              next
            end
            
            valid_indices << idx
            embeddings_to_transform << emb
          end
          
          next if embeddings_to_transform.empty?
          
          # Transform using the loaded UMAP model
          reduced_embeddings = umap_model.transform(embeddings_to_transform)
          
          # Prepare updates for valid documents
          updates = valid_indices.map.with_index do |batch_idx, transform_idx|
            {
              id: batch[batch_idx][:id],
              reduced_embedding: reduced_embeddings[transform_idx]
            }
          end
          
          # Update database
          @database.update_reduced_embeddings(updates)
          processed_count += updates.size
          
          puts "  Processed batch: #{updates.size} documents transformed"
        rescue => e
          puts "  ⚠️  Error processing batch: #{e.message}"
          error_count += batch.size
        end
      end
      
      puts "\nUMAP application complete:"
      puts "  ✓ Processed: #{processed_count} documents"
      puts "  ⚠️  Skipped: #{skipped_count} documents (invalid embeddings)" if skipped_count > 0
      puts "  ❌ Errors: #{error_count} documents" if error_count > 0
      
      {
        processed: processed_count,
        skipped: skipped_count,
        errors: error_count
      }
    end
    
    private
    
    def save_model
      return unless @umap_instance
      
      # Save the trained UMAP model for transforming new data
      @umap_instance.save_model(@model_path)
      puts "UMAP model saved to: #{@model_path}"
      
      # Save metadata about the training if we have params
      if @model_params
        metadata_path = @model_path.sub(/\.bin$/, '_metadata.json')
        metadata = {
          trained_at: Time.now.iso8601,
          n_components: @model_params[:n_components],
          n_neighbors: @model_params[:n_neighbors],
          min_dist: @model_params[:min_dist],
          document_count: @database.get_embeddings.size,
          model_version: 2  # Version 2: proper transform-based approach
        }
        File.write(metadata_path, JSON.pretty_generate(metadata))
        puts "Model metadata saved to: #{metadata_path}"
      end
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
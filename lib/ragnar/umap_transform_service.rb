require 'json'
require 'clusterkit'

module Ragnar
  # Service for applying UMAP transformations to embeddings
  # Separates transformation logic from training (UmapProcessor)
  class UmapTransformService
    attr_reader :model_path, :database
    
    def initialize(model_path: "umap_model.bin", database:)
      @model_path = model_path
      @database = database
      @umap_model = nil
      @model_metadata = nil
    end
    
    # Transform embeddings for specific documents
    # @param document_ids [Array<Integer>] IDs of documents to transform
    # @return [Hash] Results with :processed, :skipped, :errors counts
    def transform_documents(document_ids)
      return { processed: 0, skipped: 0, errors: 0 } if document_ids.empty?
      
      load_model!
      
      # Fetch documents
      documents = @database.get_documents_by_ids(document_ids)
      
      if documents.empty?
        return { processed: 0, skipped: 0, errors: 0 }
      end
      
      # Extract and validate embeddings
      valid_docs = []
      embeddings_to_transform = []
      skipped_count = 0
      
      documents.each do |doc|
        emb = doc[:embedding]
        
        if emb.nil? || !emb.is_a?(Array) || emb.empty?
          skipped_count += 1
          next
        end
        
        if emb.any? { |v| !v.is_a?(Numeric) || v.nan? || !v.finite? }
          skipped_count += 1
          next
        end
        
        valid_docs << doc
        embeddings_to_transform << emb
      end
      
      return { processed: 0, skipped: skipped_count, errors: 0 } if embeddings_to_transform.empty?
      
      # Transform using UMAP
      begin
        reduced_embeddings = @umap_model.transform(embeddings_to_transform)
        
        # Prepare updates
        updates = valid_docs.zip(reduced_embeddings).map do |doc, reduced_emb|
          {
            id: doc[:id],
            reduced_embedding: reduced_emb,
            umap_version: model_version
          }
        end
        
        # Update database
        @database.update_reduced_embeddings(updates)
        
        { processed: updates.size, skipped: skipped_count, errors: 0 }
      rescue => e
        puts "Error transforming documents: #{e.message}"
        { processed: 0, skipped: skipped_count, errors: valid_docs.size }
      end
    end
    
    # Transform a single query embedding
    # @param embedding [Array<Numeric>] Query embedding to transform
    # @return [Array<Float>, nil] Reduced embedding or nil if error
    def transform_query(embedding)
      return nil if embedding.nil? || !embedding.is_a?(Array) || embedding.empty?
      
      # Validate embedding
      if embedding.any? { |v| !v.is_a?(Numeric) || v.nan? || !v.finite? }
        puts "Warning: Invalid query embedding (contains NaN or Infinity)"
        return nil
      end
      
      load_model!
      
      begin
        # Transform returns array of arrays, get first (and only) result
        @umap_model.transform([embedding]).first
      rescue => e
        puts "Error transforming query: #{e.message}"
        nil
      end
    end
    
    # Check if a UMAP model exists
    # @return [Boolean] true if model file exists
    def model_exists?
      File.exist?(@model_path)
    end
    
    # Get metadata about the trained model
    # @return [Hash, nil] Model metadata or nil if not found
    def model_metadata
      return @model_metadata if @model_metadata
      
      metadata_path = @model_path.sub(/\.bin$/, '_metadata.json')
      return nil unless File.exist?(metadata_path)
      
      @model_metadata = JSON.parse(File.read(metadata_path), symbolize_names: true)
    rescue => e
      puts "Error loading model metadata: #{e.message}"
      nil
    end
    
    # Get the version of the current model
    # @return [Integer] Model version (timestamp of file modification)
    def model_version
      return 0 unless File.exist?(@model_path)
      File.mtime(@model_path).to_i
    end
    
    # Check if model needs retraining based on staleness
    # @return [Hash] Staleness info with :needs_retraining, :coverage_percentage
    def check_model_staleness
      return { needs_retraining: true, coverage_percentage: 0, reason: "No model exists" } unless model_exists?
      
      metadata = model_metadata
      return { needs_retraining: true, coverage_percentage: 0, reason: "No metadata found" } unless metadata
      
      trained_count = metadata[:document_count] || 0
      current_count = @database.document_count
      
      if current_count == 0
        return { needs_retraining: false, coverage_percentage: 100, reason: "No documents" }
      end
      
      coverage = (trained_count.to_f / current_count * 100).round(1)
      staleness = 100 - coverage
      
      {
        needs_retraining: staleness > 30,
        coverage_percentage: coverage,
        trained_documents: trained_count,
        current_documents: current_count,
        staleness_percentage: staleness,
        reason: staleness > 30 ? "Model covers only #{coverage}% of documents" : "Model is up to date"
      }
    end
    
    private
    
    def load_model!
      return if @umap_model
      
      unless File.exist?(@model_path)
        raise "UMAP model not found at #{@model_path}. Please train a model first using 'ragnar train-umap'."
      end
      
      @umap_model = ClusterKit::Dimensionality::UMAP.load_model(@model_path)
    end
  end
  
  # Singleton service for backwards compatibility
  # This allows the old UmapTransformService.instance pattern to work
  class UmapTransformServiceSingleton
    include Singleton
    
    def initialize
      @database = Database.new(Config.instance.database_path)
      @service = UmapTransformService.new(database: @database)
    end
    
    def transform_query(embedding, model_path = nil)
      if model_path && model_path != @service.model_path
        # Create a new service with different model path
        service = UmapTransformService.new(model_path: model_path, database: @database)
        service.transform_query(embedding)
      else
        @service.transform_query(embedding)
      end
    end
    
    def model_available?(model_path = nil)
      if model_path
        File.exist?(model_path)
      else
        @service.model_exists?
      end
    end
  end
  
  # For backwards compatibility - old code uses UmapTransformService.instance
  class << UmapTransformService
    def instance
      UmapTransformServiceSingleton.instance
    end
  end
end
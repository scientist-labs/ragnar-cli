module RubyRag
  class Database
    attr_reader :db_path, :table_name
    
    def initialize(db_path, table_name: "documents")
      @db_path = db_path
      @table_name = table_name
      ensure_database_exists
    end
    
    def add_documents(documents)
      return if documents.empty?
      
      # Convert documents to Lance-compatible format
      data = documents.map do |doc|
        {
          id: doc[:id],
          chunk_text: doc[:chunk_text],
          file_path: doc[:file_path],
          chunk_index: doc[:chunk_index],
          embedding: doc[:embedding],
          metadata: doc[:metadata].to_json
        }
      end
      
      # Define schema for the table with vector type
      embedding_size = documents.first[:embedding].size
      schema = {
        id: :string,
        chunk_text: :string,
        file_path: :string,
        chunk_index: :int64,
        embedding: { type: "vector", dimension: embedding_size },
        metadata: :string
      }
      
      # Use the new open_or_create method from Lancelot
      # This automatically handles both creating new and opening existing datasets
      dataset = Lancelot::Dataset.open_or_create(@db_path, schema: schema)
      dataset.add_documents(data)
    end
    
    def get_embeddings(limit: nil, offset: 0)
      return [] unless dataset_exists?
      
      dataset = Lancelot::Dataset.open(@db_path)
      
      # Get all documents or a subset
      docs = if limit
        dataset.first(limit)
      else
        dataset.to_a
      end
      
      # Skip offset if specified
      docs = docs.drop(offset) if offset > 0
      
      docs.map do |doc|
        {
          id: doc[:id],
          embedding: doc[:embedding],
          reduced_embedding: doc[:reduced_embedding]
        }
      end
    end
    
    def update_reduced_embeddings(updates)
      return if updates.empty?
      
      dataset = Lancelot::Dataset.open(@db_path)
      
      # Get all existing documents
      all_docs = dataset.to_a
      
      # Create a map for quick lookup
      update_map = updates.each_with_object({}) do |update, map|
        map[update[:id]] = update[:reduced_embedding]
      end
      
      # Update documents with reduced embeddings
      updated_docs = all_docs.map do |doc|
        if update_map[doc[:id]]
          doc.merge(reduced_embedding: update_map[doc[:id]])
        else
          doc
        end
      end
      
      # Need to recreate the dataset with updated data
      # First, backup the schema including the new reduced_embedding field
      embedding_size = all_docs.first[:embedding].size
      reduced_size = updates.first[:reduced_embedding].size
      
      schema = {
        id: :string,
        chunk_text: :string,
        file_path: :string,
        chunk_index: :int64,
        embedding: { type: "vector", dimension: embedding_size },
        reduced_embedding: { type: "vector", dimension: reduced_size },
        metadata: :string
      }
      
      # Remove old dataset and create new one with updated data
      FileUtils.rm_rf(@db_path)
      # Use open_or_create which will create since we just deleted the path
      dataset = Lancelot::Dataset.open_or_create(@db_path, schema: schema)
      dataset.add_documents(updated_docs)
    end
    
    def search_similar(embedding, k: 10, use_reduced: false)
      return [] unless dataset_exists?
      
      dataset = Lancelot::Dataset.open(@db_path)
      
      embedding_field = use_reduced ? :reduced_embedding : :embedding
      
      # Perform vector search
      results = dataset.vector_search(
        embedding.to_a, 
        column: embedding_field,
        limit: k
      )
      
      results.map do |row|
        {
          id: row[:id],
          chunk_text: row[:chunk_text],
          file_path: row[:file_path],
          chunk_index: row[:chunk_index],
          distance: row[:_distance],
          metadata: JSON.parse(row[:metadata] || "{}")
        }
      end
    end
    
    def get_stats
      unless dataset_exists?
        return {
          total_documents: 0,
          unique_files: 0,
          total_chunks: 0,
          with_embeddings: 0,
          with_reduced_embeddings: 0
        }
      end
      
      dataset = Lancelot::Dataset.open(@db_path)
      
      # Get all documents
      all_docs = dataset.to_a
      
      stats = {
        total_documents: all_docs.size,
        total_chunks: all_docs.size,
        unique_files: all_docs.map { |d| d[:file_path] }.uniq.size,
        with_embeddings: 0,
        with_reduced_embeddings: 0,
        avg_chunk_size: 0,
        embedding_dims: nil,
        reduced_dims: nil
      }
      
      chunk_sizes = []
      
      all_docs.each do |doc|
        if doc[:embedding] && !doc[:embedding].empty?
          stats[:with_embeddings] += 1
          stats[:embedding_dims] ||= doc[:embedding].size
        end
        
        if doc[:reduced_embedding] && !doc[:reduced_embedding].empty?
          stats[:with_reduced_embeddings] += 1
          stats[:reduced_dims] ||= doc[:reduced_embedding].size
        end
        
        chunk_sizes << doc[:chunk_text].size if doc[:chunk_text]
      end
      
      stats[:avg_chunk_size] = (chunk_sizes.sum.to_f / chunk_sizes.size).round if chunk_sizes.any?
      
      stats
    end
    
    def full_text_search(query, limit: 10)
      return [] unless dataset_exists?
      
      dataset = Lancelot::Dataset.open(@db_path)
      
      # Use Lancelot's full-text search
      results = dataset.full_text_search(
        query,
        columns: [:chunk_text],
        limit: limit
      )
      
      results.map do |row|
        {
          id: row[:id],
          chunk_text: row[:chunk_text],
          file_path: row[:file_path],
          chunk_index: row[:chunk_index],
          metadata: JSON.parse(row[:metadata] || "{}")
        }
      end
    end
    
    def dataset_exists?
      return false unless File.exist?(@db_path)
      
      begin
        Lancelot::Dataset.open(@db_path)
        true
      rescue
        false
      end
    end
    
    private
    
    def ensure_database_exists
      # Don't create directory - Lance will handle this
    end
    
    def table_exists?
      dataset_exists?
    end
  end
end
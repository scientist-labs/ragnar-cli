module RubyRag
  class CLI < Thor
    desc "index PATH", "Index text files from PATH (file or directory)"
    option :db_path, type: :string, default: RubyRag::DEFAULT_DB_PATH, desc: "Path to Lance database"
    option :chunk_size, type: :numeric, default: RubyRag::DEFAULT_CHUNK_SIZE, desc: "Chunk size in tokens"
    option :chunk_overlap, type: :numeric, default: RubyRag::DEFAULT_CHUNK_OVERLAP, desc: "Chunk overlap in tokens"
    option :model, type: :string, default: RubyRag::DEFAULT_EMBEDDING_MODEL, desc: "Embedding model to use"
    def index(path)
      unless File.exist?(path)
        say "Error: Path does not exist: #{path}", :red
        exit 1
      end
      
      say "Indexing files from: #{path}", :green
      
      indexer = Indexer.new(
        db_path: options[:db_path],
        chunk_size: options[:chunk_size],
        chunk_overlap: options[:chunk_overlap],
        embedding_model: options[:model]
      )
      
      begin
        stats = indexer.index_path(path)
        say "\nIndexing complete!", :green
        say "Files processed: #{stats[:files_processed]}"
        say "Chunks created: #{stats[:chunks_created]}"
        say "Errors: #{stats[:errors]}" if stats[:errors] > 0
      rescue => e
        say "Error during indexing: #{e.message}", :red
        exit 1
      end
    end
    
    desc "train-umap", "Train UMAP model on existing embeddings"
    option :db_path, type: :string, default: RubyRag::DEFAULT_DB_PATH, desc: "Path to Lance database"
    option :n_components, type: :numeric, default: 50, desc: "Number of dimensions for reduction"
    option :n_neighbors, type: :numeric, default: 15, desc: "Number of neighbors for UMAP"
    option :min_dist, type: :numeric, default: 0.1, desc: "Minimum distance for UMAP"
    option :model_path, type: :string, default: "umap_model.bin", desc: "Path to save UMAP model"
    def train_umap
      say "Training UMAP model on embeddings...", :green
      
      processor = UmapProcessor.new(
        db_path: options[:db_path],
        model_path: options[:model_path]
      )
      
      begin
        stats = processor.train(
          n_components: options[:n_components],
          n_neighbors: options[:n_neighbors],
          min_dist: options[:min_dist]
        )
        
        say "\nUMAP training complete!", :green
        say "Embeddings processed: #{stats[:embeddings_count]}"
        say "Original dimensions: #{stats[:original_dims]}"
        say "Reduced dimensions: #{stats[:reduced_dims]}"
        say "Model saved to: #{options[:model_path]}"
      rescue => e
        say "Error during UMAP training: #{e.message}", :red
        exit 1
      end
    end
    
    desc "apply-umap", "Apply trained UMAP model to reduce embedding dimensions"
    option :db_path, type: :string, default: RubyRag::DEFAULT_DB_PATH, desc: "Path to Lance database"
    option :model_path, type: :string, default: "umap_model.bin", desc: "Path to UMAP model"
    option :batch_size, type: :numeric, default: 100, desc: "Batch size for processing"
    def apply_umap
      unless File.exist?(options[:model_path])
        say "Error: UMAP model not found at: #{options[:model_path]}", :red
        say "Please run 'train-umap' first to create a model.", :yellow
        exit 1
      end
      
      say "Applying UMAP model to embeddings...", :green
      
      processor = UmapProcessor.new(
        db_path: options[:db_path],
        model_path: options[:model_path]
      )
      
      begin
        stats = processor.apply(batch_size: options[:batch_size])
        
        say "\nUMAP application complete!", :green
        say "Embeddings processed: #{stats[:processed]}"
        say "Already processed: #{stats[:skipped]}"
        say "Errors: #{stats[:errors]}" if stats[:errors] > 0
      rescue => e
        say "Error applying UMAP: #{e.message}", :red
        exit 1
      end
    end
    
    desc "query QUESTION", "Query the RAG system"
    option :db_path, type: :string, default: RubyRag::DEFAULT_DB_PATH, desc: "Path to Lance database"
    option :top_k, type: :numeric, default: 3, desc: "Number of top documents to use"
    option :verbose, type: :boolean, default: false, aliases: "-v", desc: "Show detailed processing steps"
    option :json, type: :boolean, default: false, desc: "Output as JSON"
    def query(question)
      processor = QueryProcessor.new(db_path: options[:db_path])
      
      begin
        result = processor.query(question, top_k: options[:top_k], verbose: options[:verbose])
        
        if options[:json]
          puts JSON.pretty_generate(result)
        else
          say "\n" + "="*60, :green
          say "Query: #{result[:query]}", :cyan
          
          if result[:clarified] != result[:query]
            say "Clarified: #{result[:clarified]}", :yellow
          end
          
          say "\nAnswer:", :green
          say result[:answer]
          
          if result[:confidence]
            say "\nConfidence: #{result[:confidence]}%", :magenta
          end
          
          if result[:sources] && !result[:sources].empty?
            say "\nSources:", :blue
            result[:sources].each_with_index do |source, idx|
              say "  #{idx + 1}. #{source[:source_file]}" if source[:source_file]
            end
          end
          
          if options[:verbose] && result[:sub_queries]
            say "\nSub-queries used:", :yellow
            result[:sub_queries].each { |sq| say "  - #{sq}" }
          end
          
          say "="*60, :green
        end
      rescue => e
        say "Error processing query: #{e.message}", :red
        say e.backtrace.first(5).join("\n") if options[:verbose]
        exit 1
      end
    end
    
    desc "stats", "Show database statistics"
    option :db_path, type: :string, default: RubyRag::DEFAULT_DB_PATH, desc: "Path to Lance database"
    def stats
      db = Database.new(options[:db_path])
      stats = db.get_stats
      
      say "\nDatabase Statistics", :green
      say "-" * 30
      say "Total documents: #{stats[:total_documents]}"
      say "Unique files: #{stats[:unique_files]}"
      say "Total chunks: #{stats[:total_chunks]}"
      say "With embeddings: #{stats[:with_embeddings]}"
      say "With reduced embeddings: #{stats[:with_reduced_embeddings]}"
      
      if stats[:total_chunks] > 0
        say "\nAverage chunk size: #{stats[:avg_chunk_size]} characters"
        say "Embedding dimensions: #{stats[:embedding_dims]}"
        say "Reduced dimensions: #{stats[:reduced_dims]}" if stats[:reduced_dims]
      end
    rescue => e
      say "Error reading database: #{e.message}", :red
      exit 1
    end
    
    desc "version", "Show version"
    def version
      say "RubyRag v#{RubyRag::VERSION}"
    end
  end
end
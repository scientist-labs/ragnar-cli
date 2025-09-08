require_relative "cli_visualization"
require_relative "config"
require "thor/interactive"
require "stringio"
require "fileutils"

module Ragnar
  class CLI < Thor
    include CLIVisualization
    include Thor::Interactive::Command

    # Configure interactive mode
    configure_interactive(
      prompt: Config.instance.interactive_prompt,
      allow_nested: false,
      history_file: Config.instance.history_file,
      default_handler: proc do |input, thor_instance|
        puts "[DEBUG] Default handler called: #{input}" if ENV["DEBUG"]

        begin
          # IMPORTANT: Use direct method call, NOT invoke(), to avoid Thor's
          # silent deduplication that prevents repeated calls to the same method
          result = thor_instance.query(input.strip)
          puts "[DEBUG] Default handler completed" if ENV["DEBUG"]
          result
        rescue => e
          puts "[DEBUG] Default handler error: #{e.message}" if ENV["DEBUG"]
          puts "[DEBUG] Backtrace: #{e.backtrace.first(3)}" if ENV["DEBUG"]
          raise e
        end
      end
    )

    # Class variables for caching expensive resources in interactive mode
    class_variable_set(:@@cached_database, nil)
    class_variable_set(:@@cached_embedder, nil)
    class_variable_set(:@@cached_llm_manager, nil)
    class_variable_set(:@@cached_query_processor, nil)
    class_variable_set(:@@cached_db_path, nil)

    desc "index PATH", "Index text files from PATH (file or directory)"
    option :db_path, type: :string, desc: "Path to Lance database (default from config)"
    option :chunk_size, type: :numeric, desc: "Chunk size in tokens (default from config)"
    option :chunk_overlap, type: :numeric, desc: "Chunk overlap in tokens (default from config)"
    option :model, type: :string, desc: "Embedding model to use (default from config)"
    def index(path)
      # Expand user paths (handle ~ in user input)
      expanded_path = File.expand_path(path)
      
      unless File.exist?(expanded_path)
        say "Error: Path does not exist: #{expanded_path}", :red
        exit 1
      end

      say "Indexing files from: #{path}", :green

      # Debug options in interactive mode
      puts "Debug - options: #{options.inspect}" if ENV['DEBUG']

      # Get config instance
      config = Config.instance
      
      # Clear database cache when indexing new content
      db_path = options[:db_path] || config.database_path
      if @@cached_db_path == db_path
        @@cached_database = nil
        @@cached_query_processor = nil
      end

      indexer = Indexer.new(
        db_path: db_path,
        chunk_size: options[:chunk_size] || config.chunk_size,
        chunk_overlap: options[:chunk_overlap] || config.chunk_overlap,
        embedding_model: options[:model] || config.embedding_model
      )

      begin
        stats = indexer.index_path(expanded_path)
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
    option :db_path, type: :string, default: Ragnar::DEFAULT_DB_PATH, desc: "Path to Lance database"
    option :n_components, type: :numeric, default: 50, desc: "Number of dimensions for reduction"
    option :n_neighbors, type: :numeric, default: 15, desc: "Number of neighbors for UMAP"
    option :min_dist, type: :numeric, default: 0.1, desc: "Minimum distance for UMAP"
    option :model_path, type: :string, desc: "Path to save UMAP model"
    def train_umap
      say "Training UMAP model on embeddings...", :green

      config = Config.instance
      # Use model_path from options if provided, otherwise use config models_dir
      model_path = if options[:model_path]
        options[:model_path]
      else
        File.join(config.models_dir, "umap_model.bin")
      end
      
      processor = UmapProcessor.new(
        db_path: options[:db_path] || config.database_path,
        model_path: model_path
      )

      begin
        stats = processor.train(
          n_components: options[:n_components] || 50,
          n_neighbors: options[:n_neighbors] || 15,
          min_dist: options[:min_dist] || 0.1
        )

        say "\nUMAP training complete!", :green
        say "Embeddings processed: #{stats[:embeddings_count]}"
        say "Original dimensions: #{stats[:original_dims]}"
        say "Reduced dimensions: #{stats[:reduced_dims]}"
        say "Model saved to: #{processor.model_path}"
      rescue => e
        say "Error during UMAP training: #{e.message}", :red
        exit 1
      end
    end

    desc "apply-umap", "Apply trained UMAP model to reduce embedding dimensions"
    option :db_path, type: :string, default: Ragnar::DEFAULT_DB_PATH, desc: "Path to Lance database"
    option :model_path, type: :string, desc: "Path to UMAP model"
    option :batch_size, type: :numeric, default: 100, desc: "Batch size for processing"
    def apply_umap
      config = Config.instance
      model_path = if options[:model_path]
        options[:model_path]
      else
        File.join(config.models_dir, "umap_model.bin")
      end

      unless File.exist?(model_path)
        say "Error: UMAP model not found at: #{model_path}", :red
        say "Please run 'train-umap' first to create a model.", :yellow
        exit 1
      end

      say "Applying UMAP model to embeddings...", :green

      processor = UmapProcessor.new(
        db_path: options[:db_path] || config.database_path,
        model_path: model_path
      )

      begin
        stats = processor.apply(batch_size: options[:batch_size] || 100)

        say "\nUMAP application complete!", :green
        say "Embeddings processed: #{stats[:processed]}"
        say "Already processed: #{stats[:skipped]}"
        say "Errors: #{stats[:errors]}" if stats[:errors] > 0
      rescue => e
        say "Error applying UMAP: #{e.message}", :red
        exit 1
      end
    end

    desc "topics", "Extract and display topics from indexed documents"
    option :db_path, type: :string, default: Ragnar::DEFAULT_DB_PATH, desc: "Path to Lance database"
    option :min_cluster_size, type: :numeric, default: 5, desc: "Minimum documents per topic"
    option :method, type: :string, default: "hybrid", desc: "Labeling method: fast, quality, or hybrid"
    option :export, type: :string, desc: "Export topics to file (json or html)"
    option :verbose, type: :boolean, default: false, aliases: "-v", desc: "Show detailed processing"
    option :summarize, type: :boolean, default: false, aliases: "-s", desc: "Generate human-readable topic summaries using LLM"
    option :llm_model, type: :string, default: "TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF", desc: "LLM model for summarization"
    option :gguf_file, type: :string, default: "tinyllama-1.1b-chat-v1.0.q4_k_m.gguf", desc: "GGUF file name for LLM model"
    def topics
      require_relative 'topic_modeling'

      say "Extracting topics from indexed documents...", :green

      # Load embeddings and documents from database - use cache in interactive mode
      database = get_cached_database(options[:db_path] || Config.instance.database_path)

      begin
        # Get all documents with embeddings
        stats = database.get_stats
        if stats[:with_embeddings] == 0
          say "No documents with embeddings found. Please index some documents first.", :red
          exit 1
        end

        say "Loading #{stats[:with_embeddings]} documents...", :yellow

        # Get all documents with embeddings
        docs_with_embeddings = database.get_all_documents_with_embeddings

        if docs_with_embeddings.empty?
          say "Could not load documents from database. Please check your database.", :red
          exit 1
        end

        # Check if we have reduced embeddings available
        first_doc = docs_with_embeddings.first
        has_reduced = first_doc[:reduced_embedding] && !first_doc[:reduced_embedding].empty?

        if has_reduced
          embeddings = docs_with_embeddings.map { |d| d[:reduced_embedding] }
          say "Using reduced embeddings (#{embeddings.first.size} dimensions)", :yellow if options[:verbose]
          # Already reduced, so don't reduce again in the engine
          reduce_dims = false
        else
          embeddings = docs_with_embeddings.map { |d| d[:embedding] }
          say "Using original embeddings (#{embeddings.first.size} dimensions)", :yellow if options[:verbose]
          # Let the engine handle dimensionality reduction if needed
          reduce_dims = true
        end

        documents = docs_with_embeddings.map { |d| d[:chunk_text] }
        metadata = docs_with_embeddings.map { |d| { file_path: d[:file_path], chunk_index: d[:chunk_index] } }

        say "Loaded #{embeddings.length} embeddings and #{documents.length} documents", :yellow if options[:verbose]

        # Initialize topic modeling engine
        engine = Ragnar::TopicModeling::Engine.new(
          min_cluster_size: options[:min_cluster_size],
          labeling_method: options[:method].to_sym,
          verbose: options[:verbose],
          reduce_dimensions: reduce_dims
        )

        # Extract topics
        say "Clustering documents...", :yellow
        topics = engine.fit(
          embeddings: embeddings,
          documents: documents,
          metadata: metadata
        )

        # Generate summaries if requested
        if options[:summarize] && topics.any?
          say "Generating topic summaries with LLM...", :yellow
          begin
            require 'red-candle'

            # Initialize LLM for summarization once
            say "Loading model: #{options[:llm_model]}", :cyan if options[:verbose]
            llm = Candle::LLM.from_pretrained(options[:llm_model], gguf_file: options[:gguf_file])

            # Add summaries to topics
            topics.each_with_index do |topic, i|
              say "  Summarizing topic #{i+1}/#{topics.length}...", :yellow if options[:verbose]
              topic.instance_variable_set(:@summary, summarize_topic(topic, llm))
            end

            say "Topic summaries generated!", :green
          rescue => e
            say "Warning: Could not generate topic summaries: #{e.message}", :yellow
            say "Proceeding without summaries...", :yellow
          end
        end

        # Display results
        display_topics(topics, show_summaries: options[:summarize])

        # Export if requested
        if options[:export]
          # Pass embeddings and cluster IDs for visualization
          export_topics(topics, options[:export], embeddings: embeddings, cluster_ids: engine.instance_variable_get(:@cluster_ids))
        end

      rescue => e
        say "Error extracting topics: #{e.message}", :red
        say e.backtrace.first(5).join("\n") if options[:verbose]
        exit 1
      end
    end

    desc "search QUERY", "Search for similar documents"
    option :database, type: :string, default: Ragnar::DEFAULT_DB_PATH, aliases: "-d", desc: "Path to Lance database"
    option :k, type: :numeric, default: 5, desc: "Number of results to return"
    option :show_scores, type: :boolean, default: false, desc: "Show similarity scores"
    def search(query_text)
      database = get_cached_database(options[:database] || Config.instance.database_path)
      embedder = get_cached_embedder()

      # Generate embedding for query
      query_embedding = embedder.embed_text(query_text)

      # Search for similar documents
      results = database.search_similar(query_embedding, k: options[:k])

      if results.empty?
        say "No results found.", :yellow
        return
      end

      say "Found #{results.length} results:\n", :green

      results.each_with_index do |result, idx|
        say "#{idx + 1}. File: #{result[:file_path]}", :cyan
        say "   Chunk: #{result[:chunk_index]}"

        if options[:show_scores]
          say "   Distance: #{result[:distance].round(4)}"
        end

        # Show preview of content
        preview = result[:chunk_text][0..200].gsub(/\s+/, ' ')
        say "   Content: #{preview}..."
        say ""
      end
    end

    desc "query QUESTION", "Query the RAG system"
    option :db_path, type: :string, default: Ragnar::DEFAULT_DB_PATH, desc: "Path to Lance database"
    option :top_k, type: :numeric, default: 3, desc: "Number of top documents to use"
    option :verbose, type: :boolean, default: false, aliases: "-v", desc: "Show detailed processing steps"
    option :json, type: :boolean, default: false, desc: "Output as JSON"
    def query(question)
      puts "Debug - Query called with: #{question.inspect}" if ENV['DEBUG']
      puts "Debug - Options: #{options.inspect}" if ENV['DEBUG']

      processor = get_cached_query_processor(options[:db_path] || Config.instance.database_path)
      puts "Debug - Processor: #{processor.class}" if ENV['DEBUG']

      begin
        result = processor.query(question, top_k: options[:top_k] || 3, verbose: options[:verbose] || false)
        puts "Debug - Result keys: #{result.keys}" if ENV['DEBUG']

        if options[:json]
          puts JSON.pretty_generate(result)
        elsif interactive?
          # Clean output for interactive mode - just answer, confidence, and sources
          say "" # Add blank line before answer for spacing
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
          
          say "" # Add blank line for spacing
        else
          # Full output for CLI mode
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

          if (options[:verbose] || false) && result[:sub_queries]
            say "\nSub-queries used:", :yellow
            result[:sub_queries].each { |sq| say "  - #{sq}" }
          end

          say "="*60, :green
        end
      rescue => e
        say "Error processing query: #{e.message}", :red
        puts "Debug - Full backtrace: #{e.backtrace.join("\n")}" if ENV['DEBUG']
        exit 1
      end
    end

    desc "stats", "Show database statistics"
    option :db_path, type: :string, default: Ragnar::DEFAULT_DB_PATH, desc: "Path to Lance database"
    def stats
      db = get_cached_database(options[:db_path] || Config.instance.database_path)
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
      say "Ragnar v#{Ragnar::VERSION}"
    end

    desc "config", "Show current configuration"
    def config
      config = Config.instance
      
      say "\nConfiguration Settings:", :cyan
      say "-" * 40
      
      if config.config_exists?
        say "Config file: #{config.config_file_path}", :green
      else
        say "Config file: None (using defaults)", :yellow
      end
      
      say "\nPaths:", :cyan
      say "  Database: #{config.database_path}"
      say "  Models: #{config.models_dir}"
      say "  History: #{config.history_file}"
      
      say "\nEmbeddings:", :cyan
      say "  Model: #{config.embedding_model}"
      say "  Chunk size: #{config.chunk_size}"
      say "  Chunk overlap: #{config.chunk_overlap}"
      
      say "\nLLM:", :cyan
      say "  Model: #{config.llm_model}"
      say "  GGUF file: #{config.llm_gguf_file}"
      
      say "\nUMAP:", :cyan
      say "  Reduced dimensions: #{config.get('umap.reduced_dimensions', Ragnar::DEFAULT_REDUCED_DIMENSIONS)}"
      say "  N neighbors: #{config.get('umap.n_neighbors', 15)}"
      say "  Min distance: #{config.get('umap.min_dist', 0.1)}"
      
      say "\nQuery:", :cyan
      say "  Top K: #{config.get('query.top_k', 3)}"
      say "  Max context tokens: #{config.get('query.max_context_tokens', 2000)}"
      say "  Query rewriting: #{config.get('query.enable_query_rewriting', true)}"
    end
    
    desc "model", "Show current LLM model information"
    def model
      config = Config.instance
      
      say "\nLLM Model Configuration:", :cyan
      say "-" * 40
      
      say "\nDefault model:", :green
      say "  Repository: #{config.llm_model}"
      say "  GGUF file: #{config.llm_gguf_file}"
      
      topic_model = config.get('llm.topic_model')
      topic_gguf = config.get('llm.topic_gguf_file')
      
      if topic_model && topic_model != config.llm_model
        say "\nTopic labeling model:", :green
        say "  Repository: #{topic_model}"
        say "  GGUF file: #{topic_gguf}"
      else
        say "\nTopic labeling: Using default model", :yellow
      end
      
      # Check if model files exist
      model_path = File.join(config.models_dir, config.llm_gguf_file)
      if File.exist?(model_path)
        size_mb = (File.size(model_path) / 1024.0 / 1024.0).round(2)
        say "\nModel file exists: #{model_path} (#{size_mb} MB)", :green
      else
        say "\nModel file not found: #{model_path}", :yellow
        say "Run 'ragnar query' to download automatically", :yellow
      end
    end

    desc "clear-cache", "Clear cached instances (useful in interactive mode)"
    def clear_cache_command
      clear_cache
      say "Cache cleared. Next commands will create fresh instances.", :green
    end

    desc "reset", "Reset Ragnar data (database, models, cache)"
    option :all, type: :boolean, default: false, aliases: "-a", desc: "Reset everything (database, models, cache)"
    option :database, type: :boolean, default: false, aliases: "-d", desc: "Reset database only"
    option :models, type: :boolean, default: false, aliases: "-m", desc: "Reset UMAP models only"
    option :cache, type: :boolean, default: false, aliases: "-c", desc: "Clear cache only"
    option :force, type: :boolean, default: false, aliases: "-f", desc: "Skip confirmation prompt"
    def reset
      # Determine what to reset
      reset_all = options[:all]
      reset_db = options[:database] || reset_all
      reset_models = options[:models] || reset_all
      reset_cache = options[:cache] || reset_all
      
      # If no specific options, default to all
      if !reset_db && !reset_models && !reset_cache
        reset_all = true
        reset_db = reset_models = reset_cache = true
      end
      
      # Build confirmation message
      items_to_reset = []
      items_to_reset << "database" if reset_db
      items_to_reset << "UMAP models" if reset_models
      items_to_reset << "cache" if reset_cache
      
      # Get paths that will be affected
      config = Config.instance
      db_path = options[:db_path] || config.database_path
      model_path = File.join(config.models_dir, "umap_model.bin")
      
      # Show what will be deleted
      say "\nWARNING: This will delete the following:", :red
      say "-" * 40
      
      if reset_db
        say "Database: #{db_path}", :cyan
        if File.exist?(db_path)
          stats = Database.new(db_path).get_stats rescue nil
          if stats
            say "  (#{stats[:total_documents]} documents, #{stats[:total_chunks]} chunks)", :white
          end
        else
          say "  (does not exist)", :white
        end
      end
      
      if reset_models
        say "UMAP models:", :cyan
        model_files = [
          model_path,
          model_path.sub(/\.bin$/, '_metadata.json'),
          model_path.sub(/\.bin$/, '_embeddings.json')  # Old format, if exists
        ]
        model_files.each do |file|
          if File.exist?(file)
            say "  #{file} (#{(File.size(file) / 1024.0).round(1)} KB)", :white
          end
        end
        if model_files.none? { |f| File.exist?(f) }
          say "  (no models found)", :white
        end
      end
      
      if reset_cache
        cache_dir = File.expand_path("~/.cache/ragnar")
        say "Cache directory: #{cache_dir}", :cyan
        if Dir.exist?(cache_dir)
          cache_size = Dir.glob(File.join(cache_dir, "**/*"))
            .select { |f| File.file?(f) }
            .sum { |f| File.size(f) } / 1024.0 / 1024.0
          say "  (#{cache_size.round(1)} MB)", :white
        else
          say "  (does not exist)", :white
        end
      end
      
      say "-" * 40
      
      # Ask for confirmation unless --force
      unless options[:force]
        message = "\nAre you sure you want to reset #{items_to_reset.join(', ')}?"
        
        # Check if we're in interactive mode
        if ENV['THOR_INTERACTIVE_SESSION'] == 'true'
          # In interactive mode, use a simple prompt
          say message, :yellow
          response = ask("Type 'yes' to confirm, anything else to cancel:", :yellow)
          confirmed = response.downcase == 'yes'
        else
          # In CLI mode, use Thor's yes? method
          confirmed = yes?(message + " (y/N)", :yellow)
        end
        
        unless confirmed
          say "\nReset cancelled.", :cyan
          return
        end
      end
      
      # Perform the reset
      say "\nResetting...", :green
      
      if reset_db && File.exist?(db_path)
        say "Removing database: #{db_path}"
        FileUtils.rm_rf(db_path)
        say "  ✓ Database removed", :green
      end
      
      if reset_models
        model_files = [
          model_path,
          model_path.sub(/\.bin$/, '_metadata.json'),
          model_path.sub(/\.bin$/, '_embeddings.json')
        ]
        model_files.each do |file|
          if File.exist?(file)
            say "Removing model file: #{file}"
            FileUtils.rm_f(file)
            say "  ✓ Removed", :green
          end
        end
      end
      
      if reset_cache
        # Clear in-memory cache
        clear_cache
        
        # Optionally clear cache directory (but preserve history)
        cache_dir = File.expand_path("~/.cache/ragnar")
        if Dir.exist?(cache_dir)
          # Preserve history file
          history_file = File.join(cache_dir, "history")
          history_content = File.read(history_file) if File.exist?(history_file)
          
          # Remove cache directory contents except history
          Dir.glob(File.join(cache_dir, "*")).each do |item|
            next if File.basename(item) == "history"
            if File.directory?(item)
              FileUtils.rm_rf(item)
            else
              FileUtils.rm_f(item)
            end
            say "Removed cache item: #{File.basename(item)}", :green
          end
        end
        say "  ✓ Cache cleared", :green
      end
      
      say "\nReset complete!", :green
      say "You can now start fresh with 'ragnar index <path>'", :cyan
    end

    desc "init-config", "Generate a configuration file with current defaults"
    option :global, type: :boolean, default: false, aliases: "-g", desc: "Create global config in home directory"
    option :force, type: :boolean, default: false, aliases: "-f", desc: "Overwrite existing config file"
    def init_config
      config = Config.instance
      
      if options[:global]
        config_path = File.expand_path('~/.ragnar.yml')
      else
        config_path = File.join(Dir.pwd, '.ragnar.yml')
      end
      
      if File.exist?(config_path) && !options[:force]
        say "Config file already exists at: #{config_path}", :yellow
        say "Use --force to overwrite, or choose a different location.", :yellow
        return
      end
      
      generated_path = config.generate_config_file(config_path)
      say "Config file created at: #{generated_path}", :green
      say "Edit this file to customize Ragnar's behavior.", :cyan
      
      if config.config_exists?
        say "\nNote: Currently using config from: #{config.config_file_path}", :yellow
      end
    end

    private

    # Cached instance helpers for interactive mode
    def get_cached_database(db_path = nil)
      # Use config default if no path provided
      db_path ||= Config.instance.database_path
      
      # Cache database per path - clear cache if path changes
      if @@cached_db_path != db_path
        @@cached_database = nil
        @@cached_db_path = db_path
        @@cached_query_processor = nil  # Also clear dependent caches
      end

      @@cached_database ||= Database.new(db_path)
    end

    def get_cached_embedder(model_name = nil)
      # Use config default if no model specified
      model_name ||= Config.instance.embedding_model
      @@cached_embedder ||= Embedder.new(model_name: model_name)
    end

    def get_cached_llm_manager
      @@cached_llm_manager ||= LLMManager.instance
    end

    def get_cached_query_processor(db_path = nil)
      # Use config default if no path provided
      db_path ||= Config.instance.database_path
      
      # Cache query processor per database path
      if @@cached_db_path != db_path || @@cached_query_processor.nil?
        @@cached_query_processor = QueryProcessor.new(db_path: db_path)
      end

      @@cached_query_processor
    end

    def clear_cache
      @@cached_database = nil
      @@cached_embedder = nil
      @@cached_llm_manager = nil
      @@cached_query_processor = nil
      @@cached_db_path = nil
    end


    def summarize_topic(topic, llm)
      # Get representative documents for context
      sample_docs = topic.representative_docs(k: 3)

      # Simple, clear prompt for summarization
      prompt = <<~PROMPT
        Summarize what connects these documents in 1-2 sentences:

        Key terms: #{topic.terms.first(5).join(', ')}

        Documents:
        #{sample_docs.map.with_index { |doc, i| "#{i+1}. #{doc}" }.join("\n")}

        Summary:
      PROMPT

      begin
        summary = llm.generate(prompt).strip
        # Clean up common artifacts
        summary = summary.lines.first&.strip || "Related documents"
        summary = summary.gsub(/^(Summary:|Topic:|Documents:)/i, '').strip
        summary.empty? ? "Documents about #{topic.terms.first(2).join(' and ')}" : summary
      rescue => e
        "Documents about #{topic.terms.first(2).join(' and ')}"
      end
    end

    def fetch_all_documents(database)
      # Temporary workaround to get all documents
      # In production, we'd add a proper method to Database class
      # For now, do a large search to get all docs

      # Get stats to determine embedding size
      stats = database.get_stats
      embedding_dims = stats[:embedding_dims] || 768

      # Generate a dummy embedding to search with
      dummy_embedding = Array.new(embedding_dims, 0.0)

      # Search for a large number to get all docs
      results = database.search_similar(dummy_embedding, k: 10000)

      # Return all results that have valid embeddings and text
      results.select do |r|
        r[:embedding] && !r[:embedding].empty? &&
        r[:chunk_text] && !r[:chunk_text].empty?
      end
    rescue => e
      say "Error loading documents: #{e.message}", :red
      say e.backtrace.first(3).join("\n") if options[:verbose]
      []
    end

    def display_topics(topics, show_summaries: false)
      say "\n" + "="*60, :green
      say "Topic Analysis Results", :cyan
      if show_summaries
        say "  (with LLM-generated summaries)", :yellow
      end
      say "="*60, :green

      if topics.empty?
        say "No topics found. Try adjusting min_cluster_size.", :yellow
        return
      end

      say "\nFound #{topics.length} topics:", :green

      # Group topics by size for better visualization
      large_topics = topics.select { |t| t.size >= 20 }
      medium_topics = topics.select { |t| t.size >= 10 && t.size < 20 }
      small_topics = topics.select { |t| t.size < 10 }

      if large_topics.any?
        say "\n" + "─" * 40, :blue
        say "MAJOR TOPICS (≥20 docs)", :blue
        say "─" * 40, :blue
        display_topic_group(large_topics, :cyan, show_summaries: show_summaries)
      end

      if medium_topics.any?
        say "\n" + "─" * 40, :yellow
        say "MEDIUM TOPICS (10-19 docs)", :yellow
        say "─" * 40, :yellow
        display_topic_group(medium_topics, :yellow, show_summaries: show_summaries)
      end

      if small_topics.any?
        say "\n" + "─" * 40, :white
        say "MINOR TOPICS (<10 docs)", :white
        say "─" * 40, :white
        display_topic_group(small_topics, :white, show_summaries: show_summaries)
      end

      # Summary statistics
      total_docs = topics.sum(&:size)
      say "\n" + "="*60, :green
      say "SUMMARY STATISTICS", :green
      say "="*60, :green
      say "  Total topics: #{topics.length}"
      say "  Documents in topics: #{total_docs}"
      say "  Average topic size: #{(total_docs.to_f / topics.length).round(1)}"

      if topics.any? { |t| t.coherence > 0 }
        avg_coherence = topics.map(&:coherence).sum / topics.length
        say "  Average coherence: #{(avg_coherence * 100).round(1)}%"
      end

      # Distribution breakdown
      say "\n  Size distribution:"
      say "    Large (≥20): #{large_topics.length} topics, #{large_topics.sum(&:size)} docs"
      say "    Medium (10-19): #{medium_topics.length} topics, #{medium_topics.sum(&:size)} docs"
      say "    Small (<10): #{small_topics.length} topics, #{small_topics.sum(&:size)} docs"
    end

    def display_topic_group(topics, color, show_summaries: false)
      topics.sort_by { |t| -t.size }.each_with_index do |topic, idx|
        say "\n#{topic.label || 'Unlabeled'} (#{topic.size} docs)", color

        # Show LLM summary if available
        if show_summaries
          summary = topic.instance_variable_get(:@summary)
          if summary
            say "  Summary: #{summary}", :green
          end
        end

        # Show coherence as a bar
        if topic.coherence > 0
          coherence_pct = (topic.coherence * 100).round(0)
          bar_length = (coherence_pct / 5).to_i
          bar = "█" * bar_length + "░" * (20 - bar_length)
          say "  Coherence: #{bar} #{coherence_pct}%"
        end

        # Compact term display
        say "  Terms: #{topic.terms.first(6).join(' • ')}" if topic.terms.any?

        # Short sample (unless we showed a summary)
        if !show_summaries && topic.representative_docs(k: 1).any?
          preview = topic.representative_docs(k: 1).first
          preview = preview[0..100] + "..." if preview.length > 100
          say "  \"#{preview}\"", :white
        end
      end
    end

    def export_topics(topics, format, embeddings: nil, cluster_ids: nil)
      case format.downcase
      when 'json'
        export_topics_json(topics)
      when 'html'
        export_topics_html(topics, embeddings: embeddings, cluster_ids: cluster_ids)
      else
        say "Unknown export format: #{format}. Use 'json' or 'html'.", :red
      end
    end

    def export_topics_json(topics)
      topics_data = topics.map do |topic|
        topic_hash = topic.to_h
        # Add summary if it exists
        summary = topic.instance_variable_get(:@summary)
        topic_hash[:summary] = summary if summary
        topic_hash
      end

      data = {
        generated_at: Time.now.iso8601,
        topics: topics_data,
        summary: {
          total_topics: topics.length,
          total_documents: topics.sum(&:size),
          average_size: (topics.sum(&:size).to_f / topics.length).round(1),
          has_summaries: topics.any? { |t| t.instance_variable_get(:@summary) }
        }
      }

      filename = "topics_#{Time.now.strftime('%Y%m%d_%H%M%S')}.json"
      File.write(filename, JSON.pretty_generate(data))
      say "Topics exported to: #{filename}", :green
    end

    def export_topics_html(topics, embeddings: nil, cluster_ids: nil)
      # Generate self-contained HTML with D3.js visualization
      html = generate_topic_visualization_html(topics, embeddings: embeddings, cluster_ids: cluster_ids)

      filename = "topics_#{Time.now.strftime('%Y%m%d_%H%M%S')}.html"
      File.write(filename, html)
      say "Topics visualization exported to: #{filename}", :green

      # Offer to open in browser
      if yes?("Open in browser?")
        system("open #{filename}") rescue nil  # macOS
        system("xdg-open #{filename}") rescue nil  # Linux
      end
    end

  end
end

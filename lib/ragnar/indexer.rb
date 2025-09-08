require 'parsekit'
require 'json'
require_relative 'umap_processor'
require_relative 'config'

module Ragnar
  class Indexer
    attr_reader :database, :chunker, :embedder

    def initialize(db_path: Ragnar::DEFAULT_DB_PATH,
                   chunk_size: Ragnar::DEFAULT_CHUNK_SIZE,
                   chunk_overlap: Ragnar::DEFAULT_CHUNK_OVERLAP,
                   embedding_model: Ragnar::DEFAULT_EMBEDDING_MODEL,
                   show_progress: true)
      @database = Database.new(db_path)
      @chunker = Chunker.new(chunk_size: chunk_size, chunk_overlap: chunk_overlap)
      @embedder = Embedder.new(model_name: embedding_model)
      @show_progress = show_progress
      @db_path = db_path
      
      # Check if UMAP model exists for auto-apply
      config = Config.instance
      @umap_model_path = File.join(config.models_dir, config.get('umap.model_filename', 'umap_model.bin'))
      @umap_available = File.exist?(@umap_model_path)
      @umap_processor = nil
    end

    def index_path(path)
      stats = {
        files_processed: 0,
        chunks_created: 0,
        errors: 0
      }

      files = collect_files(path)

      if files.empty?
        puts "No text files found at path: #{path}"
        return stats
      end

      puts "Found #{files.size} file(s) to process" if @show_progress

      file_progress = if @show_progress
        TTY::ProgressBar.new(
          "Processing [:bar] :percent :current/:total - :filename",
          total: files.size,
          bar_format: :block,
          width: 30,
          clear: true
        )
      else
        nil
      end

      files.each do |file_path|
        begin
          if file_progress
            # Update the progress bar with current filename
            filename = File.basename(file_path)
            filename = filename[0..27] + "..." if filename.length > 30
            file_progress.advance(0, filename: filename)
          end

          process_file(file_path, stats, file_progress)
          stats[:files_processed] += 1
        rescue => e
          if file_progress
            file_progress.log "Error: #{File.basename(file_path)} - #{e.message}"
          else
            puts "Error processing #{File.basename(file_path)}: #{e.message}" if @show_progress
          end
          stats[:errors] += 1
        ensure
          file_progress&.advance
        end
      end
      
      # Auto-apply UMAP if model exists and we indexed new documents
      if @umap_available && stats[:chunks_created] > 0
        apply_umap_to_new_documents(stats)
        # Also check if retraining is needed
        check_umap_retraining_needed?
      elsif !@umap_available && should_suggest_umap_training?
        suggest_umap_training
      end

      stats
    end

    def index_text(text, metadata = {})
      chunks = @chunker.chunk_text(text, metadata)
      process_chunks(chunks, metadata[:file_path] || "inline_text")
    end
    
    # Convenience methods for compatibility
    def index_files(files)
      stats = {
        files_processed: 0,
        chunks_created: 0,
        errors: 0
      }
      
      files.each do |file|
        next unless File.exist?(file)
        process_file(file, stats)
        stats[:files_processed] += 1
      end
      
      stats
    end
    
    def index_directory(dir_path)
      index_path(dir_path)
    end

    private

    def collect_files(path)
      if File.file?(path)
        [path]
      elsif File.directory?(path)
        # Now we support many more file types through parser-core
        pattern = "*.{txt,md,markdown,text,pdf,docx,doc,xlsx,xls,pptx,ppt,csv,json,xml,html,htm,rb,py,js,rs,go,java,cpp,c,h}"
        Dir.glob(File.join(path, "**", pattern))
      else
        []
      end
    end

    def process_file(file_path, stats, progress_bar = nil)
      # Extract text using parser-core
      begin
        text = extract_text_from_file(file_path)

        if text.nil? || text.strip.empty?
          progress_bar.log("  Skipped: #{File.basename(file_path)} (empty or unsupported)") if progress_bar
          return
        end

        # Create metadata
        metadata = {
          file_path: file_path,
          file_name: File.basename(file_path),
          file_type: File.extname(file_path).downcase[1..-1] || 'unknown'
        }

        # Chunk the extracted text
        chunks = @chunker.chunk_text(text, metadata)

        if chunks.empty?
          progress_bar.log("  Skipped: #{File.basename(file_path)} (text too short)") if progress_bar
          return
        end

        # Process chunks and create documents
        chunk_count = process_chunks(chunks, file_path, progress_bar)
        stats[:chunks_created] += chunk_count
      rescue => e
        if progress_bar
          progress_bar.log("  Error processing file: #{e.message}")
          progress_bar.log("  Backtrace: #{e.backtrace.first}")
        end
        raise e
      end
    end

    def process_chunks(chunks, file_path, progress_bar = nil)
      return 0 if chunks.empty?

      # Extract texts for embedding
      texts = chunks.map { |c| c[:text] }

      # Generate embeddings (silently)
      embeddings = @embedder.embed_batch(texts, show_progress: false)

      # Prepare documents for database
      documents = []
      chunks.each_with_index do |chunk, idx|
        embedding = embeddings[idx]
        next unless embedding  # Skip if embedding failed

        doc = {
          id: SecureRandom.uuid,
          chunk_text: chunk[:text],
          file_path: file_path,
          chunk_index: chunk[:index],
          embedding: embedding,
          metadata: chunk[:metadata] || {}
        }

        # Note: No need to add reduced_embedding field anymore!
        # Lancelot now supports optional fields after our fix

        documents << doc
      end

      # Store in database
      if documents.any?
        @database.add_documents(documents)
        # Successfully stored chunks (silent to preserve progress bar)
      end

      documents.size
    end

    def extract_text_from_file(file_path)
      # Use parser-core to extract text from various file formats
      begin
        ParseKit.parse_file(file_path)
      rescue => e
        # If parser-core fails, try reading as plain text for known text formats
        ext = File.extname(file_path).downcase
        if %w[.txt .md .markdown .text .log .rb .py .js .rs .go .java .cpp .c .h].include?(ext)
          File.read(file_path, encoding: 'UTF-8')
        else
          raise e
        end
      end
    end

    def self.supported_extensions
      # Extended list of supported formats through parser-core
      %w[.txt .md .markdown .text .log .csv .json .xml .html .htm
         .pdf .docx .doc .xlsx .xls .pptx .ppt
         .rb .py .js .rs .go .java .cpp .c .h]
    end

    def self.is_text_file?(file_path)
      # Check by extension
      ext = File.extname(file_path).downcase
      return true if supported_extensions.include?(ext)

      # Check if file appears to be text
      begin
        # Read first 8KB to check if it's text
        sample = File.read(file_path, 8192, mode: 'rb')
        return false if sample.nil?

        # Check for binary content
        null_count = sample.count("\x00")
        return false if null_count > 0

        # Check if mostly printable ASCII
        printable = sample.count("\t\n\r\x20-\x7E")
        ratio = printable.to_f / sample.size
        ratio > 0.9
      rescue
        false
      end
    end
    
    private
    
    def apply_umap_to_new_documents(stats)
      puts "\nApplying UMAP to new embeddings..." if @show_progress
      
      begin
        # Initialize UMAP processor if not already done
        @umap_processor ||= UmapProcessor.new(
          db_path: @db_path,
          model_path: @umap_model_path
        )
        
        # Apply UMAP to documents without reduced embeddings
        result = @umap_processor.apply(batch_size: 100)
        
        if result[:processed] > 0
          puts "✓ Applied UMAP to #{result[:processed]} documents" if @show_progress
        end
        
        stats[:umap_applied] = result[:processed]
      rescue => e
        puts "⚠️  Could not apply UMAP: #{e.message}" if @show_progress
        stats[:umap_errors] = 1
      end
    end
    
    def should_suggest_umap_training?
      # Suggest UMAP training if we have enough documents
      stats = @database.get_stats
      
      # Suggest if we have at least 100 documents and no UMAP model
      stats[:with_embeddings] >= 100 && stats[:with_reduced_embeddings] == 0
    end
    
    def suggest_umap_training
      stats = @database.get_stats
      
      puts "\n" + "="*60
      puts "💡 UMAP Training Suggestion"
      puts "="*60
      puts "You have #{stats[:with_embeddings]} documents indexed."
      puts "Training a UMAP model can significantly improve query performance."
      puts ""
      puts "To train UMAP, run:"
      puts "  ragnar train-umap"
      puts ""
      puts "This will:"
      puts "  • Reduce embedding dimensions from #{stats[:embedding_dims]} to 50-64"
      puts "  • Speed up similarity search by 5-10x"
      puts "  • Reduce memory usage"
      puts "="*60
    end
    
    def check_umap_retraining_needed?
      return false unless @umap_available
      
      # Check if model is outdated
      metadata_path = @umap_model_path.sub(/\.bin$/, '_metadata.json')
      return false unless File.exist?(metadata_path)
      
      begin
        metadata = JSON.parse(File.read(metadata_path))
        model_doc_count = metadata['document_count'] || 0
        current_doc_count = @database.get_stats[:with_embeddings]
        
        # Suggest retraining if document count has doubled
        if current_doc_count > model_doc_count * 2
          puts "\n⚠️  UMAP model may be outdated"
          puts "Model was trained on #{model_doc_count} documents, now have #{current_doc_count}"
          puts "Consider retraining with: ragnar train-umap"
          return true
        end
      rescue => e
        # Ignore metadata reading errors
      end
      
      false
    end
  end
end
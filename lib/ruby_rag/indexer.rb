module RubyRag
  class Indexer
    attr_reader :database, :chunker, :embedder
    
    def initialize(db_path: RubyRag::DEFAULT_DB_PATH, 
                   chunk_size: RubyRag::DEFAULT_CHUNK_SIZE,
                   chunk_overlap: RubyRag::DEFAULT_CHUNK_OVERLAP,
                   embedding_model: RubyRag::DEFAULT_EMBEDDING_MODEL)
      @database = Database.new(db_path)
      @chunker = Chunker.new(chunk_size: chunk_size, chunk_overlap: chunk_overlap)
      @embedder = Embedder.new(model_name: embedding_model)
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
      
      puts "Found #{files.size} file(s) to process"
      
      file_progress = TTY::ProgressBar.new(
        "Processing files [:bar] :percent :current/:total",
        total: files.size,
        bar_format: :block,
        width: 30
      )
      
      files.each do |file_path|
        begin
          process_file(file_path, stats)
          stats[:files_processed] += 1
        rescue => e
          puts "\nError processing #{file_path}: #{e.message}"
          stats[:errors] += 1
        ensure
          file_progress.advance
        end
      end
      
      stats
    end
    
    def index_text(text, metadata = {})
      chunks = @chunker.chunk_text(text, metadata)
      process_chunks(chunks, metadata[:file_path] || "inline_text")
    end
    
    private
    
    def collect_files(path)
      if File.file?(path)
        [path]
      elsif File.directory?(path)
        Dir.glob(File.join(path, "**", "*.{txt,md,markdown,text}"))
      else
        []
      end
    end
    
    def process_file(file_path, stats)
      puts "\nProcessing: #{File.basename(file_path)}"
      
      # Chunk the file
      chunks = @chunker.chunk_file(file_path)
      
      if chunks.empty?
        puts "  No chunks created (file may be empty)"
        return
      end
      
      puts "  Created #{chunks.size} chunks"
      
      # Process chunks and create documents
      chunk_count = process_chunks(chunks, file_path)
      stats[:chunks_created] += chunk_count
    end
    
    def process_chunks(chunks, file_path)
      return 0 if chunks.empty?
      
      # Extract texts for embedding
      texts = chunks.map { |c| c[:text] }
      
      # Generate embeddings
      puts "  Generating embeddings..."
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
        
        documents << doc
      end
      
      # Store in database
      if documents.any?
        @database.add_documents(documents)
        puts "  Stored #{documents.size} chunks in database"
      end
      
      documents.size
    end
    
    def self.supported_extensions
      %w[.txt .md .markdown .text .log .csv .json .xml .html .htm]
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
  end
end
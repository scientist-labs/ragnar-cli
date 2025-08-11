require 'parser_core'

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
        # Now we support many more file types through parser-core
        pattern = "*.{txt,md,markdown,text,pdf,docx,doc,xlsx,xls,pptx,ppt,csv,json,xml,html,htm,rb,py,js,rs,go,java,cpp,c,h}"
        Dir.glob(File.join(path, "**", pattern))
      else
        []
      end
    end
    
    def process_file(file_path, stats)
      puts "\nProcessing: #{File.basename(file_path)}"
      
      # Extract text using parser-core
      begin
        text = extract_text_from_file(file_path)
        
        if text.nil? || text.strip.empty?
          puts "  No text extracted (file may be empty or unsupported)"
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
          puts "  No chunks created (text too short)"
          return
        end
        
        puts "  Extracted text (#{text.size} chars) and created #{chunks.size} chunks"
        
        # Process chunks and create documents
        chunk_count = process_chunks(chunks, file_path)
        stats[:chunks_created] += chunk_count
      rescue => e
        puts "  Error processing file: #{e.message}"
        puts "  Backtrace: #{e.backtrace.first(3).join("\n    ")}"
        raise e
      end
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
        
        # Note: No need to add reduced_embedding field anymore!
        # Lancelot now supports optional fields after our fix
        
        documents << doc
      end
      
      # Store in database
      if documents.any?
        @database.add_documents(documents)
        puts "  Stored #{documents.size} chunks in database"
      end
      
      documents.size
    end
    
    def extract_text_from_file(file_path)
      # Use parser-core to extract text from various file formats
      begin
        ParserCore.parse_file(file_path)
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
  end
end
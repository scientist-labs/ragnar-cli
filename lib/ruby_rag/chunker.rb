module RubyRag
  class Chunker
    attr_reader :chunk_size, :chunk_overlap
    
    def initialize(chunk_size: RubyRag::DEFAULT_CHUNK_SIZE, chunk_overlap: RubyRag::DEFAULT_CHUNK_OVERLAP)
      @chunk_size = chunk_size
      @chunk_overlap = chunk_overlap
      @splitter = Baran::CharacterTextSplitter.new(
        chunk_size: chunk_size,
        chunk_overlap: chunk_overlap,
        separator: "\n\n",
        secondary_separator: "\n",
        keep_separator: false
      )
    end
    
    def chunk_text(text, metadata = {})
      return [] if text.nil? || text.strip.empty?
      
      # Use Baran to split the text into chunks
      chunks = @splitter.chunks(text)
      
      # Add metadata to each chunk
      chunks.map.with_index do |chunk_text, index|
        {
          text: chunk_text,
          index: index,
          metadata: metadata.merge(
            chunk_index: index,
            total_chunks: chunks.size,
            chunk_size: chunk_text.size
          )
        }
      end
    rescue => e
      puts "Error chunking text: #{e.message}"
      []
    end
    
    def chunk_file(file_path)
      unless File.exist?(file_path)
        raise "File not found: #{file_path}"
      end
      
      text = File.read(file_path, encoding: 'utf-8', invalid: :replace, undef: :replace)
      
      metadata = {
        file_path: File.absolute_path(file_path),
        file_name: File.basename(file_path),
        file_size: File.size(file_path),
        file_modified: File.mtime(file_path).iso8601
      }
      
      chunk_text(text, metadata)
    end
    
    def chunk_documents(documents)
      all_chunks = []
      
      documents.each do |doc|
        if doc.is_a?(String)
          # If it's a file path
          if File.exist?(doc)
            all_chunks.concat(chunk_file(doc))
          else
            # Treat as raw text
            all_chunks.concat(chunk_text(doc))
          end
        elsif doc.is_a?(Hash)
          # If it's a document hash with text and metadata
          text = doc[:text] || doc["text"]
          metadata = doc[:metadata] || doc["metadata"] || {}
          all_chunks.concat(chunk_text(text, metadata))
        end
      end
      
      all_chunks
    end
    
    def self.semantic_chunker(model: nil)
      # Future enhancement: Use more sophisticated chunking with semantic boundaries
      # Could use sentence embeddings to find natural break points
      Baran::RecursiveCharacterTextSplitter.new(
        chunk_size: RubyRag::DEFAULT_CHUNK_SIZE,
        chunk_overlap: RubyRag::DEFAULT_CHUNK_OVERLAP,
        separators: ["\n\n", "\n", ". ", " ", ""]
      )
    end
  end
end
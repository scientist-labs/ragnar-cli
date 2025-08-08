module RubyRag
  class Embedder
    attr_reader :model, :model_name
    
    def initialize(model_name: RubyRag::DEFAULT_EMBEDDING_MODEL)
      @model_name = model_name
      @model = load_model(model_name)
    end
    
    def embed_text(text)
      return nil if text.nil? || text.strip.empty?
      
      # Use RedCandle to generate embeddings
      embedding = @model.embed(text)
      
      # Convert to array if needed
      if embedding.respond_to?(:to_a)
        embedding.to_a
      else
        embedding
      end
    rescue => e
      puts "Error generating embedding: #{e.message}"
      nil
    end
    
    def embed_batch(texts, show_progress: true)
      embeddings = []
      
      if show_progress
        progressbar = TTY::ProgressBar.new(
          "Generating embeddings [:bar] :percent :current/:total",
          total: texts.size,
          bar_format: :block,
          width: 30
        )
      end
      
      texts.each do |text|
        embedding = embed_text(text)
        embeddings << embedding
        progressbar.advance if show_progress
      end
      
      embeddings
    end
    
    def embed_chunks(chunks, show_progress: true)
      texts = chunks.map do |chunk|
        if chunk.is_a?(Hash)
          chunk[:text] || chunk["text"]
        else
          chunk.to_s
        end
      end
      
      embed_batch(texts, show_progress: show_progress)
    end
    
    private
    
    def load_model(model_name)
      # Initialize RedCandle embedding model
      # RedCandle handles model downloading and caching automatically
      begin
        RedCandle::Embedding.new(model_name)
      rescue => e
        puts "Warning: Could not load model #{model_name}, falling back to default"
        puts "Error: #{e.message}"
        
        # Try with a simpler model name format
        if model_name.include?("/")
          simple_name = model_name.split("/").last
          RedCandle::Embedding.new(simple_name)
        else
          # Last resort: use a known working model
          RedCandle::Embedding.new("bge-small-en-v1.5")
        end
      end
    end
    
    def self.available_models
      # List of commonly used embedding models
      # This could be expanded or made dynamic
      [
        "BAAI/bge-small-en-v1.5",
        "BAAI/bge-base-en-v1.5",
        "BAAI/bge-large-en-v1.5",
        "sentence-transformers/all-MiniLM-L6-v2",
        "sentence-transformers/all-mpnet-base-v2",
        "thenlper/gte-small",
        "thenlper/gte-base",
        "thenlper/gte-large"
      ]
    end
    
    def self.model_info(model_name)
      # Provide information about embedding models
      info = {
        "BAAI/bge-small-en-v1.5" => {
          dimensions: 384,
          max_tokens: 512,
          description: "Small, fast, good quality embeddings"
        },
        "BAAI/bge-base-en-v1.5" => {
          dimensions: 768,
          max_tokens: 512,
          description: "Balanced size and quality"
        },
        "BAAI/bge-large-en-v1.5" => {
          dimensions: 1024,
          max_tokens: 512,
          description: "Large, highest quality embeddings"
        },
        "sentence-transformers/all-MiniLM-L6-v2" => {
          dimensions: 384,
          max_tokens: 256,
          description: "Fast, lightweight model"
        },
        "sentence-transformers/all-mpnet-base-v2" => {
          dimensions: 768,
          max_tokens: 384,
          description: "High quality general purpose embeddings"
        }
      }
      
      info[model_name] || { description: "Model information not available" }
    end
  end
end
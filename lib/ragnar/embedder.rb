module Ragnar
  class Embedder
    attr_reader :model, :model_name
    
    def initialize(model_name: Ragnar::DEFAULT_EMBEDDING_MODEL)
      @model_name = model_name
      @model = load_model(model_name)
    end
    
    def embed_text(text)
      return nil if text.nil? || text.empty? || (text.respond_to?(:strip) && text.strip.empty?)
      
      # Use Candle to generate embeddings
      # The embedding method returns a tensor, we need to convert to array
      embedding = @model.embedding(text)
      
      # Convert tensor to array - Candle tensors need double to_a
      # First to_a gives [tensor], second to_a on the tensor gives the float array
      if embedding.respond_to?(:to_a)
        result = embedding.to_a
        if result.is_a?(Array) && result.first.respond_to?(:to_a)
          result.first.to_a
        else
          result
        end
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
      # Initialize Candle embedding model using the new standardized from_pretrained method
      begin
        # Try to load the model using from_pretrained
        Candle::EmbeddingModel.from_pretrained(model_name)
      rescue => e
        puts "Warning: Could not load model #{model_name}, falling back to default"
        puts "Error: #{e.message}"
        
        # Fall back to default model
        begin
          Candle::EmbeddingModel.from_pretrained("jinaai/jina-embeddings-v2-base-en")
        rescue => fallback_error
          puts "Error loading fallback model: #{fallback_error.message}"
          # Last resort: try the old initialization method for backwards compatibility
          Candle::EmbeddingModel.new
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
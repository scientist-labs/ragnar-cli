module Ragnar
  # Singleton manager for LLM instances to avoid reloading models
  class LLMManager
    include Singleton
    
    def initialize
      @llms = {}
      @mutex = Mutex.new
    end
    
    # Get or create an LLM instance
    # @param model_id [String] The model identifier
    # @param gguf_file [String, nil] Optional GGUF file for quantized models
    # @return [Candle::LLM] The LLM instance
    def get_llm(model_id: "TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF", 
                gguf_file: "tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf")
      cache_key = "#{model_id}:#{gguf_file}"
      
      @mutex.synchronize do
        @llms[cache_key] ||= begin
          # Only show loading message if not in interactive mode or if verbose
          show_loading = ENV['DEBUG'] # Only show in debug mode for now
          puts "Loading LLM: #{model_id}..." if show_loading && !@llms.key?(cache_key)
          
          if gguf_file
            Candle::LLM.from_pretrained(model_id, gguf_file: gguf_file)
          else
            Candle::LLM.from_pretrained(model_id)
          end
        end
      end
    end
    
    # Clear all cached models (useful for memory management)
    def clear_cache
      @mutex.synchronize do
        @llms.clear
      end
    end
    
    # Get the default LLM for the application
    def default_llm
      get_llm
    end
  end
end
module Ragnar
  # Singleton manager for RubyLLM chat instances to avoid reloading models.
  # Supports any RubyLLM provider (red_candle for local, openai, anthropic, etc.)
  class LLMManager
    include Singleton

    def initialize
      @chats = {}
      @mutex = Mutex.new
    end

    # Get or create a RubyLLM chat instance
    # @param provider [String, Symbol] The RubyLLM provider (default from config)
    # @param model [String] The model identifier (default from config)
    # @return [RubyLLM::Chat] A cached chat instance
    def get_chat(provider: nil, model: nil)
      config = Config.instance
      provider ||= config.llm_provider
      model ||= config.llm_model

      cache_key = "#{provider}:#{model}"

      @mutex.synchronize do
        @chats[cache_key] ||= begin
          puts "Loading LLM: #{model} (#{provider})..." if ENV['DEBUG']
          RubyLLM.chat(provider: provider.to_sym, model: model)
        end
      end
    end

    # Clear all cached chat instances (useful for memory management)
    def clear_cache
      @mutex.synchronize do
        @chats.clear
      end
    end

    # Get the default chat instance for the application
    def default_chat
      get_chat
    end

    # Backwards compatibility aliases
    alias_method :get_llm, :get_chat
    alias_method :default_llm, :default_chat
  end
end

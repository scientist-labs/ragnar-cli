# frozen_string_literal: true

require 'yaml'
require 'pathname' 
require 'singleton'
require 'fileutils'

module Ragnar
  class Config
    include Singleton
    
    CONFIG_FILENAMES = ['.ragnar.yml', '.ragnarrc.yml', 'ragnar.yml'].freeze
    
    def initialize
      @config = load_config
      ensure_directories_exist
    end
    
    # Main config access method
    def get(key_path, default = nil)
      keys = key_path.split('.')
      value = keys.reduce(@config) { |config, key| config&.dig(key) }
      
      # Use default only if value is nil (not false)
      result = value.nil? ? default : value
      
      # Expand paths that start with ~
      if result.is_a?(String) && result.start_with?('~')
        File.expand_path(result)
      else
        result
      end
    end
    
    # Common config accessors
    def database_path
      get('storage.database_path', default_database_path)
    end
    
    def history_file
      get('storage.history_file', default_history_file)
    end
    
    def models_dir
      get('storage.models_dir', default_models_dir)
    end
    
    def embedding_model
      get('embeddings.model', Ragnar::DEFAULT_EMBEDDING_MODEL)
    end
    
    def chunk_size
      get('embeddings.chunk_size', Ragnar::DEFAULT_CHUNK_SIZE)
    end
    
    def chunk_overlap
      get('embeddings.chunk_overlap', Ragnar::DEFAULT_CHUNK_OVERLAP)
    end
    
    # LLM Profile support
    # Profiles allow switching between LLM providers/models via --profile flag
    # Backwards compatible: flat llm.provider/llm.default_model still work if no profiles defined

    def set_active_profile(name)
      name = name.to_s
      profiles = llm_profiles
      unless profiles.key?(name)
        available = profiles.keys.join(', ')
        raise ArgumentError, "Unknown profile '#{name}'. Available profiles: #{available}"
      end
      @active_profile = name
    end

    def llm_profile_name
      @active_profile || get('llm.default_profile', nil) || llm_profiles.keys.first || 'default'
    end

    def llm_profiles
      configured = get('llm.profiles', nil)
      if configured.is_a?(Hash) && !configured.empty?
        configured
      else
        # Backwards compat: synthesize a profile from flat keys
        {
          'default' => {
            'provider' => get('llm.provider', 'red_candle'),
            'model' => get('llm.default_model', 'MaziyarPanahi/Qwen3-4B-GGUF')
          }
        }
      end
    end

    def llm_profile
      llm_profiles[llm_profile_name] || llm_profiles.values.first
    end

    def available_profiles
      llm_profiles.keys
    end

    # Create a new RubyLLM chat instance with the active profile's settings
    def create_chat
      api_key = llm_api_key
      provider = llm_provider.to_sym

      # Configure RubyLLM with the API key if present
      if api_key
        configure_provider_api_key(provider, api_key)
      end

      RubyLLM.chat(provider: provider, model: llm_model)
    end

    def llm_provider
      llm_profile&.dig('provider') || get('llm.provider', 'red_candle')
    end

    def llm_model
      llm_profile&.dig('model') || get('llm.default_model', 'MaziyarPanahi/Qwen3-4B-GGUF')
    end

    def llm_gguf_file
      get('llm.default_gguf_file', "Qwen3-4B.Q4_K_M.gguf")
    end

    def llm_api_key
      llm_profile&.dig('api_key') || get('llm.api_key', nil)
    end
    
    def interactive_prompt
      get('interactive.prompt', "ragnar> ")
    end
    
    def quiet_mode?
      get('interactive.quiet_mode', true)
    end
    
    def show_progress?
      get('output.show_progress', true)
    end
    
    def query_top_k
      get('query.top_k', 3)
    end
    
    def enable_query_rewriting?
      get('query.enable_query_rewriting', true)
    end

    def enable_reranking?
      get('query.enable_reranking', true)
    end

    def reranker_model
      get('query.reranker_model', 'BAAI/bge-reranker-base')
    end
    
    # Config file management
    def config_file_path
      @config_file_path
    end
    
    def config_exists?
      !@config_file_path.nil?
    end
    
    def reload!
      @config = load_config
      ensure_directories_exist
    end
    
    # Generate a config file with current/default settings
    def generate_config_file(path = nil)
      path ||= File.expand_path('~/.ragnar.yml')
      
      config_content = {
        'storage' => {
          'database_path' => '~/.cache/ragnar/database',
          'models_dir' => '~/.cache/ragnar/models', 
          'history_file' => '~/.cache/ragnar/history'
        },
        'embeddings' => {
          'model' => Ragnar::DEFAULT_EMBEDDING_MODEL,
          'chunk_size' => Ragnar::DEFAULT_CHUNK_SIZE,
          'chunk_overlap' => Ragnar::DEFAULT_CHUNK_OVERLAP
        },
        'umap' => {
          'reduced_dimensions' => Ragnar::DEFAULT_REDUCED_DIMENSIONS,
          'n_neighbors' => 15,
          'min_dist' => 0.1,
          'model_filename' => 'umap_model.bin'
        },
        'llm' => {
          'default_profile' => 'red_candle',
          'profiles' => {
            'red_candle' => {
              'provider' => 'red_candle',
              'model' => 'MaziyarPanahi/Qwen3-4B-GGUF'
            },
            'opus' => {
              'provider' => 'anthropic',
              'model' => 'claude-opus-4-6'
            },
            'sonnet' => {
              'provider' => 'anthropic',
              'model' => 'claude-sonnet-4-6'
            }
          }
        },
        'query' => {
          'top_k' => 3,
          'enable_query_rewriting' => true,
          'enable_reranking' => true,
          'reranker_model' => 'BAAI/bge-reranker-base'
        },
        'interactive' => {
          'prompt' => 'ragnar> ',
          'quiet_mode' => true
        },
        'output' => {
          'show_progress' => true
        }
      }
      
      # Ensure parent directory exists
      FileUtils.mkdir_p(File.dirname(path))
      
      # Write config file with comments
      File.write(path, generate_yaml_with_comments(config_content))
      path
    end
    
    private

    def configure_provider_api_key(provider, api_key)
      case provider
      when :anthropic
        RubyLLM.configure { |c| c.anthropic_api_key = api_key }
      when :openai
        RubyLLM.configure { |c| c.openai_api_key = api_key }
      end
    end

    def load_config
      @config_file_path = find_config_file
      
      if @config_file_path && File.exist?(@config_file_path)
        YAML.load_file(@config_file_path) || {}
      else
        {}
      end
    rescue => e
      warn "Warning: Error loading config file #{@config_file_path}: #{e.message}"
      {}
    end
    
    def find_config_file
      # Search order: current directory → home directory
      search_paths = [
        Dir.pwd,
        File.expand_path('~')
      ]
      
      search_paths.each do |dir|
        CONFIG_FILENAMES.each do |filename|
          path = File.join(dir, filename)
          return path if File.exist?(path)
        end
      end
      
      nil
    end
    
    def ensure_directories_exist
      directories = [
        database_path,
        models_dir,
        File.dirname(history_file)
      ]
      
      directories.each do |dir|
        FileUtils.mkdir_p(dir) unless dir.nil?
      end
    end
    
    def default_database_path
      xdg_cache_home = ENV['XDG_CACHE_HOME'] || File.expand_path('~/.cache')
      File.join(xdg_cache_home, 'ragnar', 'database')
    end
    
    def default_history_file
      xdg_cache_home = ENV['XDG_CACHE_HOME'] || File.expand_path('~/.cache')
      File.join(xdg_cache_home, 'ragnar', 'history')
    end
    
    def default_models_dir
      xdg_cache_home = ENV['XDG_CACHE_HOME'] || File.expand_path('~/.cache')
      File.join(xdg_cache_home, 'ragnar', 'models')
    end
    
    def generate_yaml_with_comments(config_hash)
      yaml_content = YAML.dump(config_hash)
      
      # Add header comment
      commented = <<~HEADER
        # Ragnar Configuration File
        # 
        # This file configures default settings for Ragnar RAG system.
        # Save as .ragnar.yml in your project directory or ~/.ragnar.yml for global settings.
        # 
        # Search order: ./.ragnar.yml → ~/.ragnar.yml → built-in defaults
        #
        # All paths support ~ expansion (e.g., ~/.cache/ragnar/database)

      HEADER
      
      commented + yaml_content
    end
  end
end
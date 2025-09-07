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
      
      # Use default if value is nil
      result = value || default
      
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
    
    def llm_model
      get('llm.default_model', "TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF")
    end
    
    def llm_gguf_file
      get('llm.default_gguf_file', "tinyllama-1.1b-chat-v1.0.q4_k_m.gguf")
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
          'default_model' => 'TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF',
          'default_gguf_file' => 'tinyllama-1.1b-chat-v1.0.q4_k_m.gguf',
          'topic_model' => 'TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF',
          'topic_gguf_file' => 'tinyllama-1.1b-chat-v1.0.q4_k_m.gguf'
        },
        'query' => {
          'top_k' => 3,
          'max_context_tokens' => 2000,
          'enable_query_rewriting' => true
        },
        'topics' => {
          'min_cluster_size' => 5,
          'labeling_method' => 'hybrid',
          'auto_summarize' => false
        },
        'interactive' => {
          'prompt' => 'ragnar> ',
          'quiet_mode' => true,
          'save_history' => true
        },
        'output' => {
          'show_progress' => true,
          'use_colors' => true,
          'default_verbosity' => 'normal'
        }
      }
      
      # Ensure parent directory exists
      FileUtils.mkdir_p(File.dirname(path))
      
      # Write config file with comments
      File.write(path, generate_yaml_with_comments(config_content))
      path
    end
    
    private
    
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
# frozen_string_literal: true

require 'spec_helper'
require 'ragnar/config'
require 'tempfile'
require 'fileutils'

RSpec.describe Ragnar::Config do
  let(:temp_dir) { Dir.mktmpdir }
  let(:home_dir) { Dir.mktmpdir }
  
  # Helper to get a fresh config instance
  def fresh_config
    # Reset singleton
    Singleton.__init__(described_class)
    described_class.instance
  end
  
  before do
    # Change to temp directory for testing
    @original_pwd = Dir.pwd
    Dir.chdir(temp_dir)
    
    # Mock home directory expansion
    @original_home = ENV['HOME']
    ENV['HOME'] = home_dir
  end
  
  after do
    Dir.chdir(@original_pwd)
    ENV['HOME'] = @original_home
    FileUtils.rm_rf(temp_dir)
    FileUtils.rm_rf(home_dir)
  end
  
  describe '#initialize' do
    context 'without config file' do
      it 'uses default values' do
        config = fresh_config
        expect(config.database_path).to include('/.cache/ragnar/database')
        expect(config.models_dir).to include('/.cache/ragnar/models')
        expect(config.history_file).to include('/.cache/ragnar/history')
      end
      
      it 'creates necessary directories' do
        config = fresh_config
        expect(Dir.exist?(File.dirname(config.database_path))).to be true
        expect(Dir.exist?(config.models_dir)).to be true
        expect(Dir.exist?(File.dirname(config.history_file))).to be true
      end
    end
    
    context 'with local config file' do
      before do
        File.write(File.join(temp_dir, '.ragnar.yml'), <<~YAML)
          storage:
            database_path: './local_db'
            models_dir: './local_models'
          embeddings:
            model: 'custom/model'
            chunk_size: 1024
        YAML
      end
      
      it 'loads configuration from local file' do
        config = fresh_config
        expect(config.database_path).to eq('./local_db')
        expect(config.models_dir).to eq('./local_models')
        expect(config.embedding_model).to eq('custom/model')
        expect(config.chunk_size).to eq(1024)
      end
      
      it 'reports config file exists' do
        config = fresh_config
        expect(config.config_exists?).to be true
        expect(config.config_file_path).to end_with('.ragnar.yml')
      end
    end
    
    context 'with global config file' do
      before do
        File.write(File.join(home_dir, '.ragnar.yml'), <<~YAML)
          storage:
            database_path: '~/.ragnar/db'
          llm:
            default_model: 'global/model'
        YAML
      end
      
      it 'loads configuration from home directory' do
        config = fresh_config
        expect(config.llm_model).to eq('global/model')
      end
      
      it 'expands tilde in paths' do
        config = fresh_config
        expect(config.database_path).to eq(File.expand_path('~/.ragnar/db'))
      end
    end
    
    context 'with both local and global config' do
      before do
        File.write(File.join(home_dir, '.ragnar.yml'), <<~YAML)
          storage:
            database_path: '~/.ragnar/global_db'
        YAML
        
        File.write(File.join(temp_dir, '.ragnar.yml'), <<~YAML)
          storage:
            database_path: './local_db'
        YAML
      end
      
      it 'prefers local config over global' do
        config = fresh_config
        expect(config.database_path).to eq('./local_db')
      end
    end
    
    context 'with invalid YAML' do
      before do
        File.write(File.join(temp_dir, '.ragnar.yml'), "invalid: yaml: content:")
      end
      
      it 'falls back to defaults and warns' do
        config = nil
        expect { config = fresh_config }.to output(/Warning: Error loading config file/).to_stderr
        expect(config.database_path).to include('/.cache/ragnar/database')
      end
    end
  end
  
  describe '#get' do
    before do
      File.write(File.join(temp_dir, '.ragnar.yml'), <<~YAML)
        storage:
          database_path: './test_db'
        embeddings:
          model: 'test/model'
        nested:
          deep:
            value: 42
      YAML
    end
    
    it 'retrieves nested values using dot notation' do
      config = fresh_config
      expect(config.get('storage.database_path')).to eq('./test_db')
      expect(config.get('embeddings.model')).to eq('test/model')
      expect(config.get('nested.deep.value')).to eq(42)
    end
    
    it 'returns default when value is nil' do
      config = fresh_config
      expect(config.get('nonexistent.key', 'default')).to eq('default')
    end
    
    it 'expands paths starting with tilde' do
      File.write(File.join(temp_dir, '.ragnar.yml'), <<~YAML)
        storage:
          database_path: '~/my_db'
      YAML
      config = fresh_config
      
      expect(config.get('storage.database_path')).to eq(File.expand_path('~/my_db'))
    end
  end
  
  describe 'accessor methods' do
    before do
      File.write(File.join(temp_dir, '.ragnar.yml'), <<~YAML)
        storage:
          database_path: './custom_db'
          models_dir: './custom_models'
          history_file: './custom_history'
        embeddings:
          model: 'custom/embedding'
          chunk_size: 2048
          chunk_overlap: 100
        llm:
          default_model: 'custom/llm'
          default_gguf_file: 'custom.gguf'
        interactive:
          prompt: 'custom> '
          quiet_mode: false
        output:
          show_progress: false
      YAML
    end
    
    it 'provides convenient accessors for common settings' do
      config = fresh_config
      expect(config.database_path).to eq('./custom_db')
      expect(config.models_dir).to eq('./custom_models')
      expect(config.history_file).to eq('./custom_history')
      expect(config.embedding_model).to eq('custom/embedding')
      expect(config.chunk_size).to eq(2048)
      expect(config.chunk_overlap).to eq(100)
      expect(config.llm_model).to eq('custom/llm')
      expect(config.llm_gguf_file).to eq('custom.gguf')
      expect(config.interactive_prompt).to eq('custom> ')
      expect(config.quiet_mode?).to be false
      expect(config.show_progress?).to be false
    end
  end
  
  describe '#generate_config_file' do
    it 'generates a config file with default settings' do
      config = fresh_config
      config_path = File.join(temp_dir, 'generated.yml')
      result = config.generate_config_file(config_path)
      
      expect(result).to eq(config_path)
      expect(File.exist?(config_path)).to be true
      
      content = File.read(config_path)
      expect(content).to include('# Ragnar Configuration File')
      expect(content).to include('storage:')
      expect(content).to include('database_path:')
      expect(content).to include('embeddings:')
      expect(content).to include('llm:')
    end
    
    it 'creates parent directories if needed' do
      config = fresh_config
      config_path = File.join(temp_dir, 'nested', 'dir', 'config.yml')
      config.generate_config_file(config_path)
      
      expect(File.exist?(config_path)).to be true
    end
    
    it 'defaults to ~/.ragnar.yml when no path specified' do
      config = fresh_config
      result = config.generate_config_file
      expect(result).to eq(File.expand_path('~/.ragnar.yml'))
      expect(File.exist?(File.expand_path('~/.ragnar.yml'))).to be true
    end
  end
  
  describe '#reload!' do
    it 'reloads configuration from disk' do
      File.write(File.join(temp_dir, '.ragnar.yml'), <<~YAML)
        embeddings:
          model: 'original'
      YAML
      
      config = fresh_config
      expect(config.embedding_model).to eq('original')
      
      # Modify file
      File.write(File.join(temp_dir, '.ragnar.yml'), <<~YAML)
        embeddings:
          model: 'updated'
      YAML
      
      config.reload!
      expect(config.embedding_model).to eq('updated')
    end
  end
  
  describe 'config file search order' do
    it 'searches for multiple config filenames' do
      # Test .ragnarrc.yml
      File.write(File.join(temp_dir, '.ragnarrc.yml'), <<~YAML)
        embeddings:
          model: 'from_ragnarrc'
      YAML
      config = fresh_config
      
      expect(config.embedding_model).to eq('from_ragnarrc')
      
      # Test ragnar.yml (lower priority)
      File.write(File.join(temp_dir, 'ragnar.yml'), <<~YAML)
        embeddings:
          model: 'from_ragnar_yml'
      YAML
      config = fresh_config
      
      # Should still use .ragnarrc.yml since it has higher priority
      expect(config.embedding_model).to eq('from_ragnarrc')
      
      # Remove .ragnarrc.yml
      File.delete(File.join(temp_dir, '.ragnarrc.yml'))
      config = fresh_config
      
      # Now should use ragnar.yml
      expect(config.embedding_model).to eq('from_ragnar_yml')
    end
  end
  
  describe 'XDG Base Directory support' do
    it 'respects XDG_CACHE_HOME environment variable' do
      xdg_cache = File.join(temp_dir, 'xdg_cache')
      ENV['XDG_CACHE_HOME'] = xdg_cache
      
      config = fresh_config
      
      expect(config.database_path).to eq(File.join(xdg_cache, 'ragnar', 'database'))
      expect(config.models_dir).to eq(File.join(xdg_cache, 'ragnar', 'models'))
      expect(config.history_file).to eq(File.join(xdg_cache, 'ragnar', 'history'))
      
      ENV.delete('XDG_CACHE_HOME')
    end
  end
end
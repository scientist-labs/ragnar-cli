# frozen_string_literal: true

require "spec_helper"
require "fileutils"

RSpec.describe "Ragnar::CLI reset command" do
  let(:cli) { Ragnar::CLI.new }
  let(:db_path) { "./ragnar_database" }
  let(:models_dir) { File.expand_path("~/.cache/ragnar/models") }
  let(:model_path) { File.join(models_dir, "umap_model.bin") }
  let(:metadata_path) { model_path.sub(/\.bin$/, '_metadata.json') }
  let(:embeddings_path) { model_path.sub(/\.bin$/, '_embeddings.json') }
  let(:cache_dir) { File.expand_path("~/.cache/ragnar") }
  
  before do
    # Mock the Config instance
    config = instance_double(Ragnar::Config)
    allow(config).to receive(:database_path).and_return(db_path)
    allow(config).to receive(:models_dir).and_return(models_dir)
    allow(Ragnar::Config).to receive(:instance).and_return(config)
    
    # Silence output during tests
    allow(cli).to receive(:say)
    allow(cli).to receive(:ask).and_return("no")
    allow(cli).to receive(:yes?).and_return(false)
    
    # Mock file operations
    allow(File).to receive(:exist?).and_call_original
    allow(File).to receive(:size).and_call_original
    allow(Dir).to receive(:exist?).and_call_original
    allow(Dir).to receive(:glob).and_call_original
    allow(FileUtils).to receive(:rm_rf)
    allow(FileUtils).to receive(:rm_f)
  end
  
  describe "#reset" do
    context "without any options" do
      it "defaults to resetting everything" do
        allow(cli).to receive(:yes?).and_return(true)
        allow(File).to receive(:exist?).with(db_path).and_return(true)
        allow(File).to receive(:exist?).with(model_path).and_return(true)
        allow(File).to receive(:exist?).with(metadata_path).and_return(true)
        allow(File).to receive(:exist?).with(embeddings_path).and_return(true)
        allow(File).to receive(:size).with(model_path).and_return(1024)
        allow(File).to receive(:size).with(metadata_path).and_return(512)
        allow(File).to receive(:size).with(embeddings_path).and_return(2048)
        
        expect(FileUtils).to receive(:rm_rf).with(db_path)
        expect(FileUtils).to receive(:rm_f).with(model_path)
        expect(FileUtils).to receive(:rm_f).with(metadata_path)
        expect(FileUtils).to receive(:rm_f).with(embeddings_path)
        
        cli.reset
      end
      
      it "shows warning message" do
        expect(cli).to receive(:say).with("\nWARNING: This will delete the following:", :red)
        cli.reset
      end
      
      it "asks for confirmation" do
        expect(cli).to receive(:yes?).with(/Are you sure/, :yellow)
        cli.reset
      end
      
      it "cancels when user says no" do
        allow(cli).to receive(:yes?).and_return(false)
        
        expect(FileUtils).not_to receive(:rm_rf)
        expect(FileUtils).not_to receive(:rm_f)
        expect(cli).to receive(:say).with("\nReset cancelled.", :cyan)
        
        cli.reset
      end
    end
    
    context "with --force option" do
      before do
        cli.options = { force: true }
      end
      
      it "skips confirmation" do
        expect(cli).not_to receive(:yes?)
        expect(cli).not_to receive(:ask)
        
        cli.reset
      end
      
      it "proceeds with reset" do
        allow(File).to receive(:exist?).with(db_path).and_return(true)
        
        expect(FileUtils).to receive(:rm_rf).with(db_path)
        
        cli.reset
      end
    end
    
    context "with --database option" do
      before do
        cli.options = { database: true, force: true }
      end
      
      it "only resets the database" do
        allow(File).to receive(:exist?).with(db_path).and_return(true)
        
        expect(FileUtils).to receive(:rm_rf).with(db_path)
        expect(FileUtils).not_to receive(:rm_f).with(model_path)
        
        cli.reset
      end
      
      it "shows database information" do
        allow(File).to receive(:exist?).with(db_path).and_return(true)
        
        # Mock database stats
        mock_db = instance_double(Ragnar::Database)
        allow(Ragnar::Database).to receive(:new).with(db_path).and_return(mock_db)
        allow(mock_db).to receive(:get_stats).and_return({
          total_documents: 100,
          total_chunks: 200
        })
        
        expect(cli).to receive(:say).with("Database: #{db_path}", :cyan)
        expect(cli).to receive(:say).with("  (100 documents, 200 chunks)", :white)
        
        cli.reset
      end
    end
    
    context "with --models option" do
      before do
        cli.options = { models: true, force: true }
      end
      
      it "only resets UMAP models" do
        allow(File).to receive(:exist?).with(model_path).and_return(true)
        allow(File).to receive(:exist?).with(metadata_path).and_return(true)
        allow(File).to receive(:exist?).with(embeddings_path).and_return(false)
        allow(File).to receive(:size).with(model_path).and_return(1024)
        allow(File).to receive(:size).with(metadata_path).and_return(512)
        
        expect(FileUtils).not_to receive(:rm_rf).with(db_path)
        expect(FileUtils).to receive(:rm_f).with(model_path)
        expect(FileUtils).to receive(:rm_f).with(metadata_path)
        
        cli.reset
      end
      
      it "shows model file sizes" do
        allow(File).to receive(:exist?).with(model_path).and_return(true)
        allow(File).to receive(:size).with(model_path).and_return(5000 * 1024)
        
        expect(cli).to receive(:say).with("  #{model_path} (5000.0 KB)", :white)
        
        cli.reset
      end
      
      it "reports when no models exist" do
        allow(File).to receive(:exist?).with(model_path).and_return(false)
        allow(File).to receive(:exist?).with(metadata_path).and_return(false)
        allow(File).to receive(:exist?).with(embeddings_path).and_return(false)
        
        expect(cli).to receive(:say).with("  (no models found)", :white)
        
        cli.reset
      end
    end
    
    context "with --cache option" do
      before do
        cli.options = { cache: true, force: true }
      end
      
      it "only clears cache" do
        expect(FileUtils).not_to receive(:rm_rf).with(db_path)
        expect(FileUtils).not_to receive(:rm_f).with(model_path)
        
        expect(cli).to receive(:clear_cache)
        
        cli.reset
      end
      
      it "preserves history file" do
        allow(Dir).to receive(:exist?).with(cache_dir).and_return(true)
        allow(Dir).to receive(:glob).and_return([
          "#{cache_dir}/some_cache",
          "#{cache_dir}/history"
        ])
        
        expect(FileUtils).to receive(:rm_f).with("#{cache_dir}/some_cache")
        expect(FileUtils).not_to receive(:rm_f).with("#{cache_dir}/history")
        
        cli.reset
      end
    end
    
    context "with --all option" do
      before do
        cli.options = { all: true, force: true }
      end
      
      it "resets everything" do
        allow(File).to receive(:exist?).with(db_path).and_return(true)
        allow(File).to receive(:exist?).with(model_path).and_return(true)
        allow(File).to receive(:exist?).with(metadata_path).and_return(false)
        allow(File).to receive(:exist?).with(embeddings_path).and_return(false)
        allow(File).to receive(:size).with(model_path).and_return(1024)
        
        expect(FileUtils).to receive(:rm_rf).with(db_path)
        expect(FileUtils).to receive(:rm_f).with(model_path)
        expect(cli).to receive(:clear_cache)
        
        cli.reset
      end
    end
    
    context "in interactive mode" do
      before do
        ENV['THOR_INTERACTIVE_SESSION'] = 'true'
        cli.options = {}
      end
      
      after do
        ENV.delete('THOR_INTERACTIVE_SESSION')
      end
      
      it "uses ask instead of yes? for confirmation" do
        expect(cli).not_to receive(:yes?)
        expect(cli).to receive(:ask).with(/Type 'yes' to confirm/, :yellow).and_return("no")
        
        cli.reset
      end
      
      it "requires explicit 'yes' text" do
        expect(cli).to receive(:ask).and_return("yes")
        allow(File).to receive(:exist?).with(db_path).and_return(true)
        
        expect(FileUtils).to receive(:rm_rf).with(db_path)
        
        cli.reset
      end
      
      it "cancels on any other input" do
        expect(cli).to receive(:ask).and_return("y")  # Not "yes"
        
        expect(FileUtils).not_to receive(:rm_rf)
        expect(cli).to receive(:say).with("\nReset cancelled.", :cyan)
        
        cli.reset
      end
    end
    
    context "completion message" do
      before do
        cli.options = { force: true }
        allow(File).to receive(:exist?).and_return(false)
      end
      
      it "shows success message" do
        expect(cli).to receive(:say).with("\nReset complete!", :green)
        expect(cli).to receive(:say).with("You can now start fresh with 'ragnar index <path>'", :cyan)
        
        cli.reset
      end
    end
  end
end
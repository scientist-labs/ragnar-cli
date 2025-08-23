# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ragnar::UmapProcessor do
  let(:temp_db) { Tempfile.new(["test_umap", ".lance"]) }
  let(:database) { Ragnar::Database.new(temp_db.path) }
  let(:processor) { described_class.new(db_path: temp_db.path) }

  before do
    # Add some test documents with embeddings
    test_docs = [
      {
        text: "Test document 1",
        embedding: Array.new(384) { rand },
        metadata: { source: "doc1" }
      },
      {
        text: "Test document 2",
        embedding: Array.new(384) { rand },
        metadata: { source: "doc2" }
      }
    ]
    
    database.add_documents(test_docs)
  end

  after do
    temp_db.close
    temp_db.unlink
    # Clean up model files
    model_path = processor.model_path
    FileUtils.rm_f(model_path) if File.exist?(model_path)
  end

  describe "#initialize" do
    it "creates a processor instance" do
      expect(processor).to be_a(described_class)
    end

    it "initializes with the correct database" do
      expect(processor.instance_variable_get(:@database)).to be_a(Ragnar::Database)
    end
  end

  describe "#train with threading" do
    it "handles IOError in progress bar thread gracefully" do
      # This tests that our IOError handling works
      allow_any_instance_of(TTY::ProgressBar).to receive(:advance).and_raise(IOError, "stream closed")
      
      # Mock ClusterKit to avoid actual UMAP training
      mock_umap = double("UMAP")
      allow(ClusterKit::Dimensionality::UMAP).to receive(:new).and_return(mock_umap)
      allow(mock_umap).to receive(:fit_transform).and_return([[0.1, 0.2], [0.3, 0.4]])
      
      suppress_stdout do
        expect { processor.train(n_components: 2, n_neighbors: 3) }.not_to raise_error
      end
    end

    it "handles SystemCallError in progress bar thread gracefully" do
      allow_any_instance_of(TTY::ProgressBar).to receive(:advance).and_raise(SystemCallError, "pipe closed")
      
      # Mock ClusterKit to avoid actual UMAP training
      mock_umap = double("UMAP")
      allow(ClusterKit::Dimensionality::UMAP).to receive(:new).and_return(mock_umap)
      allow(mock_umap).to receive(:fit_transform).and_return([[0.1, 0.2], [0.3, 0.4]])
      
      suppress_stdout do
        expect { processor.train(n_components: 2) }.not_to raise_error
      end
    end

    it "completes training even when progress bar fails" do
      allow_any_instance_of(TTY::ProgressBar).to receive(:finish).and_raise(IOError, "stream closed")
      
      # Mock ClusterKit to avoid actual UMAP training
      mock_umap = double("UMAP")
      allow(ClusterKit::Dimensionality::UMAP).to receive(:new).and_return(mock_umap)
      allow(mock_umap).to receive(:fit_transform).and_return([[0.1, 0.2], [0.3, 0.4]])
      
      suppress_stdout do
        result = processor.train(n_components: 2)
        expect(result).to be_a(Hash)
        expect(result[:embeddings_count]).to eq(2)
      end
    end
  end

  describe "#train with empty database" do
    it "handles empty database gracefully" do
      empty_db = Tempfile.new(["empty", ".lance"])
      empty_processor = described_class.new(db_path: empty_db.path)
      
      suppress_stdout do
        result = empty_processor.train
        expect(result).to be_nil
      end
      
      empty_db.close
      empty_db.unlink
    end
  end

  describe "model persistence" do
    it "uses the correct model path" do
      expect(processor.model_path).to eq("umap_model.bin")
    end

    it "can be initialized with custom model path" do
      custom_processor = described_class.new(
        db_path: temp_db.path,
        model_path: "custom_model.bin"
      )
      expect(custom_processor.model_path).to eq("custom_model.bin")
    end
  end
end
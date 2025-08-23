# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ragnar::UmapProcessor do
  let(:temp_dir) { Dir.mktmpdir }
  let(:temp_db) { File.join(temp_dir, "test_umap.lance") }
  let(:processor) { described_class.new(db_path: temp_db) }

  after do
    # Clean up temp directory
    FileUtils.rm_rf(temp_dir) if Dir.exist?(temp_dir)
  end

  describe "#initialize" do
    it "creates a processor instance" do
      expect(processor).to be_a(described_class)
    end

    it "initializes with the correct database" do
      expect(processor.instance_variable_get(:@database)).to be_a(Ragnar::Database)
    end

    it "uses default model path" do
      expect(processor.model_path).to eq("umap_model.bin")
    end

    it "can be initialized with custom model path" do
      custom_processor = described_class.new(
        db_path: temp_db,
        model_path: "custom_model.bin"
      )
      expect(custom_processor.model_path).to eq("custom_model.bin")
    end
  end

  describe "#train" do
    context "with empty database" do
      it "raises error when database is empty" do
        suppress_stdout do
          expect { processor.train }.to raise_error(RuntimeError, /No embeddings found/)
        end
      end
    end

    context "with test data" do
      before do
        # Add minimal test data
        database = Ragnar::Database.new(temp_db)
        test_docs = [
          {
            text: "Test doc 1",
            embedding: Array.new(384) { 0.1 },
            metadata: { source: "test1" }
          },
          {
            text: "Test doc 2",
            embedding: Array.new(384) { 0.2 },
            metadata: { source: "test2" }
          }
        ]
        database.add_documents(test_docs)

        # Mock ClusterKit to avoid actual UMAP training
        mock_umap = double("UMAP")
        allow(ClusterKit::Dimensionality::UMAP).to receive(:new).and_return(mock_umap)
        allow(mock_umap).to receive(:fit_transform).and_return([[0.1, 0.2], [0.3, 0.4]])
        allow(mock_umap).to receive(:save_model)
        allow(ClusterKit::Dimensionality::UMAP).to receive(:save_data)
      end

      it "trains successfully with mocked UMAP" do
        suppress_stdout do
          result = processor.train(n_components: 2)
          expect(result).to be_a(Hash)
          expect(result[:embeddings_count]).to eq(2)
          expect(result[:original_dims]).to eq(384)
          expect(result[:reduced_dims]).to eq(2)
        end
      end

      it "adjusts n_neighbors when too large for sample size" do
        suppress_stdout do
          result = processor.train(n_components: 2, n_neighbors: 50)
          expect(result).to be_a(Hash)
          # With 2 samples, n_neighbors should be adjusted to 1
        end
      end
    end
  end

  describe "#apply" do
    it "requires a trained model" do
      suppress_stdout do
        expect { processor.apply }.to raise_error(RuntimeError, /Cached embeddings not found/)
      end
    end
  end
end
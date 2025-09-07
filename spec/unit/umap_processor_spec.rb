# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ragnar::UmapProcessor do
  let(:db_path) { temp_db_path }
  let(:model_path) { File.join(temp_dir, "test_umap_model.bin") }
  let(:processor) { described_class.new(db_path: db_path, model_path: model_path) }
  let(:sample_embeddings) { Array.new(15) { fake_embedding_for("doc") } }
  let(:sample_docs) do
    sample_embeddings.map.with_index do |embedding, i|
      { id: "doc_#{i}", embedding: embedding, reduced_embedding: nil }
    end
  end

  before do
    # Mock the database to avoid actual database operations
    allow_any_instance_of(Ragnar::Database).to receive(:get_embeddings).and_return(sample_docs)
    allow_any_instance_of(Ragnar::Database).to receive(:update_reduced_embeddings)
  end

  describe "#initialize" do
    it "initializes with database and model path" do
      expect(processor.database).to be_a(Ragnar::Database)
      expect(processor.model_path).to eq(model_path)
    end

    it "uses default paths when not specified" do
      default_processor = described_class.new
      expect(default_processor.model_path).to eq("umap_model.bin")
    end
  end

  describe "#train" do
    before do
      # Mock ClusterKit UMAP
      @mock_umap = double("UMAP")
      allow(ClusterKit::Dimensionality::UMAP).to receive(:new).and_return(@mock_umap)
      allow(@mock_umap).to receive(:fit_transform).and_return(sample_embeddings.map { |e| e[0..9] })
      allow(@mock_umap).to receive(:save_model)
      allow(ClusterKit::Dimensionality::UMAP).to receive(:save_data)
      
      # Mock stdout to avoid print statements during tests
      allow_any_instance_of(Ragnar::UmapProcessor).to receive(:puts)
    end

    context "with valid embeddings" do
      it "trains UMAP model successfully" do
        result = processor.train(n_components: 10, n_neighbors: 5)

        expect(result).to include(
          embeddings_count: 15,
          original_dims: 384,
          reduced_dims: 10
        )
        expect(@mock_umap).to have_received(:fit_transform)
        expect(@mock_umap).to have_received(:save_model).with(model_path)
      end

      it "accepts custom parameters" do
        processor.train(n_components: 20, n_neighbors: 10, min_dist: 0.2)

        # The processor will adjust parameters, so just verify it was called with reasonable values
        expect(ClusterKit::Dimensionality::UMAP).to have_received(:new) do |args|
          expect(args[:n_neighbors]).to eq(10)
          expect(args[:n_components]).to be_between(2, 20)
        end
      end

      it "adjusts n_neighbors when too large for sample size" do
        # Use exactly 10 embeddings to pass the minimum check
        small_docs = sample_docs.first(10)
        allow_any_instance_of(Ragnar::Database).to receive(:get_embeddings).and_return(small_docs)

        processor.train(n_neighbors: 15)

        # Should adjust n_neighbors to be less than sample size
        expect(ClusterKit::Dimensionality::UMAP).to have_received(:new) do |args|
          expect(args[:n_neighbors]).to be < 10
        end
      end

      it "adjusts n_components when too large for sample size" do
        # Use exactly 10 embeddings to pass the minimum check
        small_docs = sample_docs.first(10)
        allow_any_instance_of(Ragnar::Database).to receive(:get_embeddings).and_return(small_docs)

        result = processor.train(n_components: 20)

        expect(result[:reduced_dims]).to be <= 9  # Should be adjusted down
      end
    end

    context "with invalid embeddings" do
      it "raises error when no embeddings found" do
        allow_any_instance_of(Ragnar::Database).to receive(:get_embeddings).and_return([])

        expect {
          processor.train
        }.to raise_error("No embeddings found in database. Please index some documents first.")
      end

      it "raises error when too few embeddings" do
        small_docs = sample_docs.first(3)
        allow_any_instance_of(Ragnar::Database).to receive(:get_embeddings).and_return(small_docs)

        expect {
          processor.train
        }.to raise_error(/Too few valid embeddings/)
      end

      it "filters out embeddings with inconsistent dimensions" do
        mixed_docs = sample_docs.dup
        mixed_docs[0][:embedding] = [1.0, 2.0]  # Different dimension

        allow_any_instance_of(Ragnar::Database).to receive(:get_embeddings).and_return(mixed_docs)

        result = processor.train

        expect(result[:embeddings_count]).to eq(14)  # Should filter out the inconsistent one
      end

      it "filters out embeddings with NaN values" do
        nan_docs = sample_docs.dup
        nan_docs[0][:embedding] = Array.new(384, Float::NAN)

        allow_any_instance_of(Ragnar::Database).to receive(:get_embeddings).and_return(nan_docs)

        result = processor.train

        expect(result[:embeddings_count]).to eq(14)  # Should filter out the NaN one
      end

      it "filters out embeddings with infinite values" do
        inf_docs = sample_docs.dup
        inf_docs[0][:embedding] = Array.new(384, Float::INFINITY)

        allow_any_instance_of(Ragnar::Database).to receive(:get_embeddings).and_return(inf_docs)

        result = processor.train

        expect(result[:embeddings_count]).to eq(14)  # Should filter out the infinite one
      end
    end

    context "when UMAP training fails" do
      before do
        allow(@mock_umap).to receive(:fit_transform).and_raise("UMAP training error")
      end

      it "provides helpful error message" do
        expect {
          processor.train
        }.to raise_error(RuntimeError, /UMAP training failed/)
      end
    end
  end

  describe "#apply" do
    let(:umap_model) { instance_double(ClusterKit::Dimensionality::UMAP) }
    let(:reduced_embeddings) { Array.new(15) { Array.new(50, 0.5) } }

    before do
      # Mock loading UMAP model
      allow(processor).to receive(:load_umap_model).and_return(umap_model)
      allow(umap_model).to receive(:transform).and_return(reduced_embeddings)
      allow_any_instance_of(Ragnar::UmapProcessor).to receive(:puts)
    end

    context "with valid embeddings" do
      it "transforms and applies reduced embeddings to database" do
        # Mock the specific database instance
        allow(processor.database).to receive(:update_reduced_embeddings)
        
        result = processor.apply

        expect(result).to eq({
          processed: 15,
          skipped: 0,
          errors: 0
        })

        # Verify UMAP transform was called
        expect(umap_model).to have_received(:transform).with(kind_of(Array))
        
        # Verify database was updated with reduced embeddings
        expect(processor.database).to have_received(:update_reduced_embeddings).with(
          array_including(
            hash_including(id: "doc_0", reduced_embedding: kind_of(Array)),
            hash_including(id: "doc_14", reduced_embedding: kind_of(Array))
          )
        )
      end

      it "accepts custom batch size" do
        result = processor.apply(batch_size: 5)

        expect(result[:processed]).to eq(15)
      end
    end

    context "with no embeddings in database" do
      before do
        allow_any_instance_of(Ragnar::Database).to receive(:get_embeddings).and_return([])
      end

      it "returns zero processed count" do
        result = processor.apply

        expect(result).to eq({
          processed: 0,
          skipped: 0,
          errors: 0
        })
      end
    end

    context "with invalid embeddings" do
      before do
        # Add some invalid embeddings to the test data
        invalid_docs = [
          { id: "invalid_1", embedding: nil },
          { id: "invalid_2", embedding: [1.0, Float::NAN, 3.0] },
          { id: "invalid_3", embedding: [1.0, Float::INFINITY, 3.0] }
        ]
        all_docs = sample_docs + invalid_docs
        allow_any_instance_of(Ragnar::Database).to receive(:get_embeddings).and_return(all_docs)
        
        # Transform only returns results for valid embeddings
        valid_reduced = Array.new(15) { Array.new(50, 0.5) }
        allow(umap_model).to receive(:transform).and_return(valid_reduced)
      end

      it "skips invalid embeddings and processes valid ones" do
        result = processor.apply

        expect(result[:processed]).to eq(15)
        expect(result[:skipped]).to eq(3)
        expect(result[:errors]).to eq(0)
      end
    end

    context "when model loading fails" do
      before do
        allow(processor).to receive(:load_umap_model).and_raise("UMAP model not found")
      end

      it "raises error for missing model" do
        expect {
          processor.apply
        }.to raise_error("UMAP model not found")
      end
    end
  end

  describe ".optimal_dimensions" do
    it "calculates optimal dimensions based on ratio" do
      result = described_class.optimal_dimensions(1000, target_ratio: 0.1)
      expect(result).to eq(100)
    end

    it "enforces minimum of 50 dimensions" do
      result = described_class.optimal_dimensions(200, target_ratio: 0.1)
      expect(result).to eq(50)  # 200 * 0.1 = 20, but minimum is 50
    end

    it "uses default ratio when not specified" do
      result = described_class.optimal_dimensions(1000)
      expect(result).to eq(100)  # 1000 * 0.1
    end
  end

  describe "private methods" do
    let(:reduced_embeddings) { Array.new(15) { Array.new(50, 0.5) } }
    
    describe "#save_model" do
      let(:mock_umap) { double("UMAP") }
      
      before do
        # Set up processor with mocked UMAP instance and params
        processor.instance_variable_set(:@umap_instance, mock_umap)
        processor.instance_variable_set(:@model_params, {
          n_components: 50,
          n_neighbors: 15,
          min_dist: 0.1
        })
        
        allow(mock_umap).to receive(:save_model)
        allow(File).to receive(:write)
        allow_any_instance_of(Ragnar::UmapProcessor).to receive(:puts)
        allow_any_instance_of(Ragnar::Database).to receive(:get_embeddings).and_return(sample_docs)
      end

      it "saves model and metadata" do
        processor.send(:save_model)

        expect(mock_umap).to have_received(:save_model).with(model_path)
        
        metadata_path = model_path.sub(/\.bin$/, '_metadata.json')
        expect(File).to have_received(:write).with(
          metadata_path,
          kind_of(String)
        )
      end

      it "skips saving when no model or embeddings" do
        processor.instance_variable_set(:@umap_instance, nil)

        expect {
          processor.send(:save_model)
        }.not_to raise_error

        expect(mock_umap).not_to have_received(:save_model)
      end
    end

    # Note: load_model method has been removed in the new implementation
    # as we now use load_umap_model to load the actual UMAP model for transformation

    describe "#load_umap_model" do
      let(:mock_umap_model) { double("UMAP Model") }
      
      before do
        # Use call_original for File.exist? by default, only stub specific path  
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(model_path).and_return(true)
        allow(ClusterKit::Dimensionality::UMAP).to receive(:load_model).and_return(mock_umap_model)
        allow_any_instance_of(Ragnar::UmapProcessor).to receive(:puts)
      end

      it "loads UMAP model from file" do
        result = processor.send(:load_umap_model)

        expect(result).to eq(mock_umap_model)
        expect(ClusterKit::Dimensionality::UMAP).to have_received(:load_model).with(model_path)
      end

      it "caches loaded model for subsequent calls" do
        # Reset any existing model cache and clear previous expectations
        processor.instance_variable_set(:@umap_instance, nil)
        # Clear the mock so we can track fresh calls
        allow(ClusterKit::Dimensionality::UMAP).to receive(:load_model).and_return(mock_umap_model)
        
        processor.send(:load_umap_model)
        processor.send(:load_umap_model)

        # Should only call load_model once due to caching
        expect(ClusterKit::Dimensionality::UMAP).to have_received(:load_model).once
      end

      it "raises error when model file not found" do
        allow(File).to receive(:exist?).with(model_path).and_return(false)

        expect {
          processor.send(:load_umap_model)
        }.to raise_error(/UMAP model not found/)
      end
    end
  end
end
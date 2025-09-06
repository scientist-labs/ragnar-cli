# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ragnar::UmapTransformService do
  let(:service) { described_class.instance }
  let(:model_path) { File.join(temp_dir, "test_umap.bin") }
  let(:query_embedding) { fake_embedding_for("query") }
  let(:reduced_embedding) { Array.new(50, 0.5) }

  before do
    # Reset singleton state for each test
    service.instance_variable_set(:@umap_model, nil)
    service.instance_variable_set(:@model_path, "umap_model.bin")
    
    # Mock stdout to avoid print statements
    allow(service).to receive(:puts)
  end

  describe "#transform_query" do
    context "with available UMAP model" do
      before do
        @mock_umap = double("UMAP")
        allow(@mock_umap).to receive(:transform).with([query_embedding]).and_return([reduced_embedding])
        allow(service).to receive(:load_model)
        service.instance_variable_set(:@umap_model, @mock_umap)
      end

      it "transforms query embedding using UMAP model" do
        result = service.transform_query(query_embedding, model_path)

        expect(result).to eq(reduced_embedding)
        expect(@mock_umap).to have_received(:transform).with([query_embedding])
      end

      it "uses default model path when not specified" do
        # Mock that no model is loaded initially
        service.instance_variable_set(:@umap_model, nil)
        allow(service).to receive(:load_model).with("umap_model.bin") do
          service.instance_variable_set(:@umap_model, @mock_umap)
        end

        service.transform_query(query_embedding)

        expect(service).to have_received(:load_model).with("umap_model.bin")
      end

      it "loads model if not already loaded" do
        service.instance_variable_set(:@umap_model, nil)
        allow(service).to receive(:load_model).with(model_path) do
          service.instance_variable_set(:@umap_model, @mock_umap)
        end

        service.transform_query(query_embedding, model_path)

        expect(service).to have_received(:load_model).with(model_path)
      end
    end

    context "when UMAP model loading fails" do
      before do
        allow(service).to receive(:load_model).and_raise("Model not found")
        allow(service).to receive(:knn_approximate_transform).and_return(reduced_embedding)
      end

      it "falls back to k-NN approximation" do
        result = service.transform_query(query_embedding, model_path)

        expect(result).to eq(reduced_embedding)
        expect(service).to have_received(:knn_approximate_transform).with(query_embedding)
      end
    end

    context "when both methods fail" do
      before do
        allow(service).to receive(:load_model).and_raise("Model not found")
        allow(service).to receive(:knn_approximate_transform).and_raise("No neighbors found")
      end

      it "raises the fallback error" do
        expect {
          service.transform_query(query_embedding, model_path)
        }.to raise_error("No neighbors found")
      end
    end
  end

  describe "#model_available?" do
    context "when model file exists" do
      before do
        allow(File).to receive(:exist?).with(model_path).and_return(true)
      end

      it "returns true" do
        expect(service.model_available?(model_path)).to be true
      end
    end

    context "when model file doesn't exist but database has reduced embeddings" do
      before do
        allow(File).to receive(:exist?).and_return(false)
        
        mock_database = double("Database")
        allow(mock_database).to receive(:get_stats).and_return({ with_reduced_embeddings: 5 })
        allow(Ragnar::Database).to receive(:new).and_return(mock_database)
      end

      it "returns true for fallback availability" do
        expect(service.model_available?(model_path)).to be true
      end
    end

    context "when neither model nor reduced embeddings available" do
      before do
        allow(File).to receive(:exist?).and_return(false)
        
        mock_database = double("Database")
        allow(mock_database).to receive(:get_stats).and_return({ with_reduced_embeddings: 0 })
        allow(Ragnar::Database).to receive(:new).and_return(mock_database)
      end

      it "returns false" do
        expect(service.model_available?(model_path)).to be false
      end
    end
  end

  describe "private methods" do
    describe "#load_model" do
      before do
        @mock_umap = double("UMAP")
        allow(File).to receive(:exist?).with(model_path).and_return(true)
        allow(ClusterKit::Dimensionality::UMAP).to receive(:load_model).and_return(@mock_umap)
      end

      it "loads UMAP model from file" do
        service.send(:load_model, model_path)

        expect(service.instance_variable_get(:@umap_model)).to eq(@mock_umap)
        expect(ClusterKit::Dimensionality::UMAP).to have_received(:load_model).with(model_path)
      end

      it "raises error when model file not found" do
        allow(File).to receive(:exist?).with(model_path).and_return(false)

        expect {
          service.send(:load_model, model_path)
        }.to raise_error(/UMAP model not found/)
      end
    end

    describe "#knn_approximate_transform" do
      let(:mock_database) { double("Database") }
      let(:neighbor_docs) do
        [
          { id: "1", embedding: fake_embedding_for("similar"), reduced_embedding: [0.1, 0.2, 0.3] },
          { id: "2", embedding: fake_embedding_for("close"), reduced_embedding: [0.2, 0.3, 0.4] },
          { id: "3", embedding: fake_embedding_for("near"), reduced_embedding: [0.3, 0.4, 0.5] }
        ]
      end

      before do
        allow(Ragnar::Database).to receive(:new).and_return(mock_database)
        allow(mock_database).to receive(:get_stats).and_return({ with_reduced_embeddings: 3 })
        allow(mock_database).to receive(:get_embeddings).and_return(neighbor_docs)
        
        # Mock distance calculation to return predictable values
        allow(service).to receive(:euclidean_distance).and_return(0.1, 0.2, 0.3)
      end

      it "approximates transform using k-nearest neighbors" do
        result = service.send(:knn_approximate_transform, query_embedding)

        expect(result).to be_an(Array)
        expect(result.size).to eq(3)  # Same as reduced embedding dimensions
        
        # Should use weighted average of neighbor reduced embeddings
        expect(result).to all(be_a(Numeric))
      end

      it "raises error when no reduced embeddings available" do
        allow(mock_database).to receive(:get_stats).and_return({ with_reduced_embeddings: 0 })

        expect {
          service.send(:knn_approximate_transform, query_embedding)
        }.to raise_error("No reduced embeddings available in database")
      end

      it "raises error when no neighbors found" do
        allow(mock_database).to receive(:get_embeddings).and_return([])

        expect {
          service.send(:knn_approximate_transform, query_embedding)
        }.to raise_error("No neighbors found for transform")
      end
    end

    describe "#euclidean_distance" do
      let(:vec1) { [1.0, 2.0, 3.0] }
      let(:vec2) { [4.0, 5.0, 6.0] }

      it "calculates euclidean distance correctly" do
        result = service.send(:euclidean_distance, vec1, vec2)
        expected = Math.sqrt(9 + 9 + 9)  # sqrt((1-4)² + (2-5)² + (3-6)²)
        expect(result).to be_within(0.001).of(expected)
      end

      it "returns infinity for vectors of different sizes" do
        vec3 = [1.0, 2.0]
        result = service.send(:euclidean_distance, vec1, vec3)
        expect(result).to eq(Float::INFINITY)
      end

      it "handles zero distance (identical vectors)" do
        result = service.send(:euclidean_distance, vec1, vec1)
        expect(result).to eq(0.0)
      end
    end
  end
end
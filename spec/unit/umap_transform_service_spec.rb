# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ragnar::UmapTransformService do
  let(:db_path) { temp_db_path }
  let(:database) { Ragnar::Database.new(db_path) }
  let(:model_path) { File.join(temp_dir, "test_umap.bin") }
  let(:service) { described_class.new(model_path: model_path, database: database) }
  let(:query_embedding) { fake_embedding_for("query") }
  let(:reduced_embedding) { Array.new(50, 0.5) }
  
  before do
    # Mock stdout to avoid print statements
    allow(service).to receive(:puts)
    allow_any_instance_of(Ragnar::UmapTransformService).to receive(:puts)
  end

  describe "#transform_documents" do
    let(:document_ids) { ["doc_1", "doc_2", "doc_3"] }
    let(:documents) do
      [
        { id: "doc_1", embedding: fake_embedding_for("doc1"), chunk_text: "Text 1" },
        { id: "doc_2", embedding: fake_embedding_for("doc2"), chunk_text: "Text 2" },
        { id: "doc_3", embedding: fake_embedding_for("doc3"), chunk_text: "Text 3" }
      ]
    end
    
    context "with valid documents" do
      before do
        @mock_umap = double("UMAP")
        allow(@mock_umap).to receive(:transform).and_return(Array.new(3) { reduced_embedding })
        allow(service).to receive(:load_model!)
        service.instance_variable_set(:@umap_model, @mock_umap)
        
        allow(database).to receive(:get_documents_by_ids).with(document_ids).and_return(documents)
        allow(database).to receive(:update_reduced_embeddings)
        allow(service).to receive(:model_version).and_return(123456)
      end
      
      it "transforms document embeddings" do
        result = service.transform_documents(document_ids)
        
        expect(result[:processed]).to eq(3)
        expect(result[:skipped]).to eq(0)
        expect(result[:errors]).to eq(0)
        
        expect(@mock_umap).to have_received(:transform).with(
          array_including(kind_of(Array), kind_of(Array), kind_of(Array))
        )
      end
      
      it "updates database with reduced embeddings" do
        service.transform_documents(document_ids)
        
        expect(database).to have_received(:update_reduced_embeddings).with(
          array_including(
            hash_including(id: "doc_1", reduced_embedding: kind_of(Array), umap_version: 123456)
          )
        )
      end
    end
    
    context "with invalid embeddings" do
      let(:invalid_documents) do
        [
          { id: "doc_1", embedding: nil, chunk_text: "Text 1" },
          { id: "doc_2", embedding: [1.0, Float::NAN, 3.0], chunk_text: "Text 2" },
          { id: "doc_3", embedding: fake_embedding_for("doc3"), chunk_text: "Text 3" }
        ]
      end
      
      before do
        @mock_umap = double("UMAP")
        allow(@mock_umap).to receive(:transform).and_return([reduced_embedding])
        allow(service).to receive(:load_model!)
        service.instance_variable_set(:@umap_model, @mock_umap)
        
        allow(database).to receive(:get_documents_by_ids).with(document_ids).and_return(invalid_documents)
        allow(database).to receive(:update_reduced_embeddings)
        allow(service).to receive(:model_version).and_return(123456)
      end
      
      it "skips invalid embeddings" do
        result = service.transform_documents(document_ids)
        
        expect(result[:processed]).to eq(1)
        expect(result[:skipped]).to eq(2)
        expect(result[:errors]).to eq(0)
      end
    end
    
    context "when transformation fails" do
      before do
        @mock_umap = double("UMAP")
        allow(@mock_umap).to receive(:transform).and_raise("UMAP error")
        allow(service).to receive(:load_model!)
        service.instance_variable_set(:@umap_model, @mock_umap)
        
        allow(database).to receive(:get_documents_by_ids).with(document_ids).and_return(documents)
      end
      
      it "returns error count" do
        result = service.transform_documents(document_ids)
        
        expect(result[:processed]).to eq(0)
        expect(result[:skipped]).to eq(0)
        expect(result[:errors]).to eq(3)
      end
    end
  end

  describe "#transform_query" do
    context "with valid embedding" do
      before do
        @mock_umap = double("UMAP")
        allow(@mock_umap).to receive(:transform).with([query_embedding]).and_return([reduced_embedding])
        allow(service).to receive(:load_model!)
        service.instance_variable_set(:@umap_model, @mock_umap)
      end

      it "transforms query embedding using UMAP model" do
        result = service.transform_query(query_embedding)

        expect(result).to eq(reduced_embedding)
        expect(@mock_umap).to have_received(:transform).with([query_embedding])
      end
    end

    context "with invalid embedding" do
      it "returns nil for nil embedding" do
        result = service.transform_query(nil)
        expect(result).to be_nil
      end
      
      it "returns nil for embedding with NaN" do
        invalid_embedding = [1.0, Float::NAN, 3.0]
        result = service.transform_query(invalid_embedding)
        expect(result).to be_nil
      end
      
      it "returns nil for embedding with Infinity" do
        invalid_embedding = [1.0, Float::INFINITY, 3.0]
        result = service.transform_query(invalid_embedding)
        expect(result).to be_nil
      end
    end

    context "when transformation fails" do
      before do
        @mock_umap = double("UMAP")
        allow(@mock_umap).to receive(:transform).and_raise("UMAP error")
        allow(service).to receive(:load_model!)
        service.instance_variable_set(:@umap_model, @mock_umap)
      end

      it "returns nil and prints error" do
        expect(service).to receive(:puts).with(/Error transforming query/)
        result = service.transform_query(query_embedding)
        expect(result).to be_nil
      end
    end
  end

  describe "#model_exists?" do
    context "when model file exists" do
      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(model_path).and_return(true)
      end

      it "returns true" do
        expect(service.model_exists?).to be true
      end
    end

    context "when model file doesn't exist" do
      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(model_path).and_return(false)
      end

      it "returns false" do
        expect(service.model_exists?).to be false
      end
    end
  end

  describe "#model_metadata" do
    let(:metadata_path) { model_path.sub(/\.bin$/, '_metadata.json') }
    let(:metadata) do
      {
        trained_at: "2024-01-01T00:00:00Z",
        n_components: 50,
        n_neighbors: 15,
        document_count: 100,
        model_version: 2
      }
    end
    
    context "when metadata file exists" do
      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(metadata_path).and_return(true)
        allow(File).to receive(:read).with(metadata_path).and_return(metadata.to_json)
      end
      
      it "returns parsed metadata" do
        result = service.model_metadata
        expect(result[:n_components]).to eq(50)
        expect(result[:document_count]).to eq(100)
      end
      
      it "caches metadata for subsequent calls" do
        service.model_metadata
        service.model_metadata
        expect(File).to have_received(:read).once
      end
    end
    
    context "when metadata file doesn't exist" do
      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(metadata_path).and_return(false)
      end
      
      it "returns nil" do
        expect(service.model_metadata).to be_nil
      end
    end
  end

  describe "#model_version" do
    context "when model file exists" do
      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(model_path).and_return(true)
        allow(File).to receive(:mtime).with(model_path).and_return(Time.at(123456))
      end
      
      it "returns file modification time as integer" do
        expect(service.model_version).to eq(123456)
      end
    end
    
    context "when model file doesn't exist" do
      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(model_path).and_return(false)
      end
      
      it "returns 0" do
        expect(service.model_version).to eq(0)
      end
    end
  end

  describe "#check_model_staleness" do
    context "when no model exists" do
      before do
        allow(service).to receive(:model_exists?).and_return(false)
      end
      
      it "indicates retraining needed" do
        result = service.check_model_staleness
        expect(result[:needs_retraining]).to be true
        expect(result[:coverage_percentage]).to eq(0)
        expect(result[:reason]).to eq("No model exists")
      end
    end
    
    context "when model exists with metadata" do
      let(:metadata) do
        {
          document_count: 70
        }
      end
      
      before do
        allow(service).to receive(:model_exists?).and_return(true)
        allow(service).to receive(:model_metadata).and_return(metadata)
        allow(database).to receive(:document_count).and_return(100)
      end
      
      it "calculates staleness correctly" do
        result = service.check_model_staleness
        expect(result[:coverage_percentage]).to eq(70.0)
        expect(result[:staleness_percentage]).to eq(30.0)
        expect(result[:needs_retraining]).to be false
      end
      
      context "when staleness exceeds threshold" do
        before do
          allow(database).to receive(:document_count).and_return(200)
        end
        
        it "indicates retraining needed" do
          result = service.check_model_staleness
          expect(result[:coverage_percentage]).to eq(35.0)
          expect(result[:staleness_percentage]).to eq(65.0)
          expect(result[:needs_retraining]).to be true
          expect(result[:reason]).to include("Model covers only 35.0% of documents")
        end
      end
    end
  end

  describe "private methods" do
    describe "#load_model!" do
      context "when model file exists" do
        before do
          allow(File).to receive(:exist?).and_call_original
          allow(File).to receive(:exist?).with(model_path).and_return(true)
          @mock_umap = double("UMAP")
          allow(ClusterKit::Dimensionality::UMAP).to receive(:load_model).with(model_path).and_return(@mock_umap)
        end
        
        it "loads UMAP model from file" do
          service.send(:load_model!)
          expect(service.instance_variable_get(:@umap_model)).to eq(@mock_umap)
        end
        
        it "only loads once when called multiple times" do
          service.send(:load_model!)
          service.send(:load_model!)
          expect(ClusterKit::Dimensionality::UMAP).to have_received(:load_model).once
        end
      end
      
      context "when model file doesn't exist" do
        before do
          allow(File).to receive(:exist?).and_call_original
          allow(File).to receive(:exist?).with(model_path).and_return(false)
        end
        
        it "raises error with helpful message" do
          expect {
            service.send(:load_model!)
          }.to raise_error(/UMAP model not found.*train-umap/)
        end
      end
    end
  end
end

# Test the backward compatibility singleton
RSpec.describe Ragnar::UmapTransformServiceSingleton do
  let(:singleton) { Ragnar::UmapTransformService.instance }
  let(:query_embedding) { fake_embedding_for("query") }
  let(:reduced_embedding) { Array.new(50, 0.5) }
  
  before do
    # Reset singleton for each test
    Singleton.__init__(Ragnar::UmapTransformServiceSingleton)
    allow_any_instance_of(Ragnar::UmapTransformService).to receive(:puts)
  end
  
  describe "#transform_query" do
    it "delegates to the internal service" do
      service = singleton.instance_variable_get(:@service)
      allow(service).to receive(:transform_query).with(query_embedding).and_return(reduced_embedding)
      
      result = singleton.transform_query(query_embedding)
      expect(result).to eq(reduced_embedding)
    end
    
    context "with custom model path" do
      let(:custom_path) { "/custom/path/model.bin" }
      
      it "creates new service with custom path" do
        allow_any_instance_of(Ragnar::UmapTransformService).to receive(:transform_query).and_return(reduced_embedding)
        
        result = singleton.transform_query(query_embedding, custom_path)
        expect(result).to eq(reduced_embedding)
      end
    end
  end
  
  describe "#model_available?" do
    it "checks default model when no path specified" do
      service = singleton.instance_variable_get(:@service)
      allow(service).to receive(:model_exists?).and_return(true)
      
      expect(singleton.model_available?).to be true
    end
    
    it "checks specific file when path provided" do
      custom_path = "/custom/model.bin"
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(custom_path).and_return(true)
      
      expect(singleton.model_available?(custom_path)).to be true
    end
  end
end
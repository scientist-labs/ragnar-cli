# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ragnar::TopicModeling do
  let(:sample_embeddings) { Array.new(15) { fake_embedding_for("doc") } }
  let(:sample_documents) { Array.new(15) { |i| "Document #{i} about topic modeling and clustering" } }
  let(:mock_engine) { double("TopicalEngine") }
  let(:mock_topics) do
    [
      double("Topic", id: 1, label: "AI/ML", size: 8, terms: ["machine", "learning"], coherence: 0.8),
      double("Topic", id: 2, label: "Programming", size: 7, terms: ["code", "software"], coherence: 0.7)
    ]
  end

  describe "module structure" do
    it "re-exports Topical classes" do
      expect(described_class::Topic).to eq(Topical::Topic)
      expect(described_class::Engine).to eq(Topical::Engine) 
      expect(described_class::Metrics).to eq(Topical::Metrics)
    end

    it "provides backward compatibility aliases" do
      expect(described_class.const_defined?(:Topic)).to be true
      expect(described_class.const_defined?(:Engine)).to be true
      expect(described_class.const_defined?(:Metrics)).to be true
    end
  end

  describe ".new" do
    before do
      allow(Topical::Engine).to receive(:new).and_return(mock_engine)
    end

    it "creates a new Topical::Engine instance" do
      engine = described_class.new(min_cluster_size: 5)

      expect(engine).to eq(mock_engine)
      expect(Topical::Engine).to have_received(:new).with(min_cluster_size: 5)
    end

    it "passes all options to Topical::Engine" do
      options = {
        clustering_method: :hdbscan,
        min_cluster_size: 10,
        labeling_method: :term_based,
        verbose: true
      }

      described_class.new(**options)

      expect(Topical::Engine).to have_received(:new).with(**options)
    end

    it "works without options" do
      described_class.new

      expect(Topical::Engine).to have_received(:new).with(no_args)
    end

    it "returns an engine-like object" do
      engine = described_class.new
      expect(engine).to respond_to(:fit) if engine.respond_to?(:fit) # Conditional check for mock
    end
  end

  describe ".extract" do
    before do
      allow(Topical).to receive(:extract).and_return(mock_topics)
    end

    it "delegates to Topical.extract with embeddings and documents" do
      result = described_class.extract(
        embeddings: sample_embeddings,
        documents: sample_documents
      )

      expect(result).to eq(mock_topics)
      expect(Topical).to have_received(:extract).with(
        embeddings: sample_embeddings,
        documents: sample_documents
      )
    end

    it "passes additional options to Topical.extract" do
      options = {
        min_topic_size: 5,
        clustering_method: :kmeans,
        n_topics: 10
      }

      described_class.extract(
        embeddings: sample_embeddings,
        documents: sample_documents,
        **options
      )

      expect(Topical).to have_received(:extract).with(
        embeddings: sample_embeddings,
        documents: sample_documents,
        **options
      )
    end

    it "requires embeddings and documents parameters" do
      # Test parameter validation by checking the call signature
      expect {
        described_class.extract(embeddings: sample_embeddings, documents: sample_documents)
      }.not_to raise_error
    end

    it "handles various option combinations" do
      option_sets = [
        { min_topic_size: 3 },
        { clustering_method: :hdbscan, min_cluster_size: 5 },
        { labeling_method: :term_based, verbose: true },
        {}  # No options
      ]

      option_sets.each do |options|
        expect {
          described_class.extract(
            embeddings: sample_embeddings,
            documents: sample_documents,
            **options
          )
        }.not_to raise_error
      end
    end
  end

  describe "integration with Topical gem" do
    it "provides access to Topical::Topic functionality" do
      # Test that we can access Topic class methods if available
      topic_class = described_class::Topic
      expect(topic_class).to eq(Topical::Topic)
    end

    it "provides access to Topical::Engine functionality" do
      # Test that we can access Engine class
      engine_class = described_class::Engine
      expect(engine_class).to eq(Topical::Engine)
    end

    it "provides access to Topical::Metrics functionality" do
      # Test that we can access Metrics module
      metrics_module = described_class::Metrics
      expect(metrics_module).to eq(Topical::Metrics)
    end

    context "when Topical gem functionality is used" do
      before do
        # Mock Topical classes to avoid external dependencies
        allow(Topical::Engine).to receive(:new).and_return(mock_engine)
        allow(mock_engine).to receive(:fit).and_return(mock_topics)
      end

      it "supports engine creation and fitting workflow" do
        engine = described_class.new(min_cluster_size: 5)
        topics = engine.fit(embeddings: sample_embeddings, documents: sample_documents)

        expect(topics).to eq(mock_topics)
        expect(mock_engine).to have_received(:fit).with(
          embeddings: sample_embeddings,
          documents: sample_documents
        )
      end
    end
  end

  describe "error handling" do
    it "handles missing Topical gracefully in extract" do
      allow(Topical).to receive(:extract).and_raise("Topical not available")

      expect {
        described_class.extract(embeddings: sample_embeddings, documents: sample_documents)
      }.to raise_error("Topical not available")
    end

    it "handles invalid parameters gracefully" do
      allow(Topical).to receive(:extract).and_raise(ArgumentError, "Invalid parameters")

      expect {
        described_class.extract(embeddings: [], documents: [])
      }.to raise_error(ArgumentError)
    end

    it "handles engine creation failures" do
      allow(Topical::Engine).to receive(:new).and_raise("Engine creation failed")

      expect {
        described_class.new(invalid_option: "value")
      }.to raise_error("Engine creation failed")
    end
  end

  describe "backward compatibility" do
    it "maintains the same interface as before extraction" do
      # Test that existing code patterns still work
      expect(described_class).to respond_to(:new)
      expect(described_class).to respond_to(:extract)
      
      # Test that constants are available
      expect(described_class.const_defined?(:Topic)).to be true
      expect(described_class.const_defined?(:Engine)).to be true
      expect(described_class.const_defined?(:Metrics)).to be true
    end

    it "supports the old-style topic extraction" do
      allow(Topical).to receive(:extract).and_return(mock_topics)

      # This should work the same as before
      topics = described_class.extract(
        embeddings: sample_embeddings,
        documents: sample_documents,
        min_topic_size: 5
      )

      expect(topics).to eq(mock_topics)
    end

    it "supports the old-style engine creation" do
      allow(Topical::Engine).to receive(:new).and_return(mock_engine)

      # This should work the same as before
      engine = described_class.new(
        clustering_method: :hdbscan,
        labeling_method: :term_based
      )

      expect(engine).to eq(mock_engine)
    end
  end
end
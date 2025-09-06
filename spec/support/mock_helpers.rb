# frozen_string_literal: true

module MockHelpers
  # Stub embeddings to return consistent fake vectors
  def stub_embeddings
    # Stub the model loading to avoid actually loading the embedding model
    allow_any_instance_of(Ragnar::Embedder).to receive(:load_model).and_return(mock_embedding_model)
    
    # Also stub Candle::Embedding if it's used directly
    if defined?(Candle::Embedding)
      allow(Candle::Embedding).to receive(:new).and_return(mock_embedding_model)
    end
    
    # Stub the Embedder class methods directly for extra safety
    allow_any_instance_of(Ragnar::Embedder).to receive(:embed_text) do |_, text|
      text.nil? || text.empty? ? nil : fake_embedding_for(text)
    end
    
    allow_any_instance_of(Ragnar::Embedder).to receive(:embed_batch) do |_, texts|
      texts.map { |text| fake_embedding_for(text) }
    end
  end
  
  # Stub LLM to avoid loading models
  def stub_llm
    mock_llm = double("LLM")
    allow(mock_llm).to receive(:chat) do |prompt|
      "Mock response for: #{prompt[0..50]}..."
    end
    allow(mock_llm).to receive(:generate) do |prompt|
      "Mock generated text for: #{prompt[0..50]}..."
    end
    
    # Stub LLMManager
    if defined?(Ragnar::LLMManager)
      allow_any_instance_of(Ragnar::LLMManager).to receive(:get_llm).and_return(mock_llm)
      allow_any_instance_of(Ragnar::LLMManager).to receive(:default_llm).and_return(mock_llm)
    end
    
    # Stub QueryRewriter to return predictable results
    if defined?(Ragnar::QueryRewriter)
      allow_any_instance_of(Ragnar::QueryRewriter).to receive(:rewrite) do |_, query|
        {
          'clarified_intent' => "Clarified: #{query}",
          'query_type' => 'factual',
          'context_needed' => 'moderate',
          'sub_queries' => [query, "Related to #{query}"],
          'key_terms' => query.split(' ').take(3)
        }
      end
    end
  end
  
  # Create a mock embedding model
  def mock_embedding_model
    double("EmbeddingModel").tap do |model|
      allow(model).to receive(:embedding) do |text|
        # Return something that responds to to_a like the real model
        [fake_embedding_for(text)]
      end
      allow(model).to receive(:embed) do |text|
        fake_embedding_for(text)
      end
    end
  end
  
  # Generate consistent fake embeddings based on text
  def fake_embedding_for(text, dimensions = 384)
    # Use hash of text to generate consistent embeddings
    seed = text.hash
    rng = Random.new(seed)
    Array.new(dimensions) { rng.rand }
  end
  
  # Mock database that works in memory
  def mock_database
    double("Database").tap do |db|
      documents = []
      
      allow(db).to receive(:add_documents) do |docs|
        documents.concat(docs)
        true
      end
      
      allow(db).to receive(:count) { documents.size }
      
      allow(db).to receive(:search_similar) do |embedding, k: 10|
        # Return some fake results
        documents.take(k).map.with_index do |doc, i|
          {
            id: doc[:id],
            chunk_text: doc[:chunk_text],
            file_path: doc[:file_path],
            distance: 0.1 * (i + 1),
            metadata: doc[:metadata] || {}
          }
        end
      end
      
      allow(db).to receive(:dataset_exists?).and_return(true)
      allow(db).to receive(:get_stats) do
        {
          document_count: documents.size,
          total_documents: documents.size,
          unique_files: documents.map { |d| d[:file_path] }.uniq.size,
          total_chunks: documents.size,
          with_embeddings: documents.count { |d| d[:embedding] },
          with_reduced_embeddings: 0,
          total_size_mb: 0.1
        }
      end
    end
  end
  
  # Stub topic modeling
  def stub_topic_modeling
    allow(Topical).to receive(:extract) do |embeddings:, documents:, **options|
      # Return fake topics
      [
        Topical::Topic.new(
          id: 0,
          size: documents.size / 2,
          terms: %w[topic one terms],
          label: "Topic 1",
          documents: documents.take(documents.size / 2)
        ),
        Topical::Topic.new(
          id: 1,
          size: documents.size / 2,
          terms: %w[topic two terms],
          label: "Topic 2", 
          documents: documents.drop(documents.size / 2)
        )
      ]
    end
  end
end
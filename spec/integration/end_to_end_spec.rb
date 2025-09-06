# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe "End-to-end RAG pipeline", :integration, :real_embeddings do
  let(:db_path) { temp_db_path }
  
  # Only run these if explicitly requested
  before do
    skip "Set RUN_INTEGRATION=true to run integration tests" unless ENV['RUN_INTEGRATION']
  end
  
  it "indexes documents and answers questions" do
    # Step 1: Create test documents
    docs_dir = temp_dir
    File.write(File.join(docs_dir, "ruby.txt"), 
      "Ruby is a dynamic, open source programming language with a focus on simplicity and productivity. " \
      "It has an elegant syntax that is natural to read and easy to write. " \
      "Ruby was created by Yukihiro Matsumoto in the mid-1990s.")
    
    File.write(File.join(docs_dir, "python.txt"),
      "Python is a high-level, interpreted programming language with dynamic semantics. " \
      "Its high-level built-in data structures make it attractive for Rapid Application Development. " \
      "Python was created by Guido van Rossum and first released in 1991.")
    
    # Step 2: Index the documents
    indexer = Ragnar::Indexer.new(db_path: db_path, show_progress: false)
    stats = suppress_output { indexer.index_path(docs_dir) }
    
    expect(stats[:files_processed]).to eq(2)
    expect(stats[:chunks_created]).to be > 0
    
    # Step 3: Query the indexed documents
    processor = Ragnar::QueryProcessor.new(db_path: db_path)
    result = suppress_output { processor.query("Who created Ruby?", top_k: 2) }
    
    expect(result[:answer]).to include("Matsumoto")
    expect(result[:sources]).not_to be_empty
    
    # Step 4: Verify database stats
    database = Ragnar::Database.new(db_path)
    db_stats = database.get_stats
    
    expect(db_stats[:total_documents]).to be > 0
    expect(db_stats[:unique_files]).to eq(2)
  end
  
  it "performs topic modeling on indexed documents" do
    # Prepare documents
    docs_dir = temp_dir
    
    # Create documents with distinct topics (need at least 10 for clustering)
    # AI/ML Topic (4 docs)
    File.write(File.join(docs_dir, "ai1.txt"),
      "Machine learning is a subset of artificial intelligence. " \
      "Neural networks are used in deep learning. " \
      "AI models can learn from data patterns.")
    
    File.write(File.join(docs_dir, "ai2.txt"),
      "Natural language processing enables computers to understand human text. " \
      "Large language models like GPT use transformers architecture. " \
      "AI can generate human-like text responses.")
      
    File.write(File.join(docs_dir, "ai3.txt"),
      "Computer vision allows machines to interpret visual information. " \
      "Convolutional neural networks are used for image recognition. " \
      "AI can identify objects in photographs.")
      
    File.write(File.join(docs_dir, "ai4.txt"),
      "Reinforcement learning trains agents through reward systems. " \
      "Deep Q-networks combine neural networks with Q-learning. " \
      "AI can learn to play games and control robots.")
    
    # Web Development Topic (3 docs)
    File.write(File.join(docs_dir, "web1.txt"),
      "Web development involves HTML, CSS, and JavaScript. " \
      "React and Vue are popular frontend frameworks. " \
      "Node.js enables server-side JavaScript development.")
    
    File.write(File.join(docs_dir, "web2.txt"),
      "RESTful APIs enable communication between web services. " \
      "HTTP methods like GET and POST handle requests. " \
      "JSON is commonly used for data exchange.")
      
    File.write(File.join(docs_dir, "web3.txt"),
      "Responsive web design adapts to different screen sizes. " \
      "CSS Grid and Flexbox provide layout solutions. " \
      "Progressive web apps offer native-like experiences.")
    
    # Database Topic (3 docs)  
    File.write(File.join(docs_dir, "db1.txt"),
      "Databases store structured data efficiently. " \
      "SQL is used for relational database queries. " \
      "Indexes improve query performance significantly.")
      
    File.write(File.join(docs_dir, "db2.txt"),
      "NoSQL databases like MongoDB store documents. " \
      "Key-value stores provide simple data access. " \
      "Graph databases model relationships between entities.")
      
    File.write(File.join(docs_dir, "db3.txt"),
      "Database transactions ensure data consistency. " \
      "ACID properties guarantee reliable operations. " \
      "Backup and recovery protect against data loss.")
    
    # Index documents
    indexer = Ragnar::Indexer.new(db_path: db_path, show_progress: false)
    suppress_output { indexer.index_path(docs_dir) }
    
    # Extract topics using Ragnar's topic modeling
    database = Ragnar::Database.new(db_path)
    docs = database.get_all_documents_with_embeddings
    
    skip "Need at least 10 documents for topic modeling" if docs.size < 10
    
    embeddings = docs.map { |d| d[:embedding] }
    documents = docs.map { |d| d[:chunk_text] }
    metadata = docs.map { |d| { file_path: d[:file_path], chunk_index: d[:chunk_index] } }
    
    # Use Ragnar's topic modeling engine
    engine = Ragnar::TopicModeling::Engine.new(
      min_cluster_size: 2,
      labeling_method: :term_based,
      verbose: false,
      reduce_dimensions: true
    )
    
    topics = engine.fit(
      embeddings: embeddings,
      documents: documents,
      metadata: metadata
    )
    
    expect(topics).not_to be_empty
    expect(topics.length).to be >= 2  # Should find AI and web topics
    topics.each do |topic|
      expect(topic.terms).not_to be_empty
      expect(topic.size).to be >= 2
    end
  end
end
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
    
    # Create documents with distinct topics
    File.write(File.join(docs_dir, "tech1.txt"),
      "Machine learning is a subset of artificial intelligence. " \
      "Neural networks are used in deep learning. " \
      "AI models can learn from data.")
    
    File.write(File.join(docs_dir, "tech2.txt"),
      "Web development involves HTML, CSS, and JavaScript. " \
      "React and Vue are popular frontend frameworks. " \
      "Node.js enables server-side JavaScript.")
    
    File.write(File.join(docs_dir, "tech3.txt"),
      "Databases store structured data. " \
      "SQL is used for relational databases. " \
      "NoSQL databases like MongoDB are document-oriented.")
    
    # Index documents
    indexer = Ragnar::Indexer.new(db_path: db_path, show_progress: false)
    suppress_output { indexer.index_path(docs_dir) }
    
    # Extract topics
    database = Ragnar::Database.new(db_path)
    docs = database.get_all_documents_with_embeddings
    
    skip "Need at least 10 documents for topic modeling" if docs.size < 10
    
    embeddings = docs.map { |d| d[:embedding] }
    documents = docs.map { |d| d[:chunk_text] }
    
    topics = Topical.extract(
      embeddings: embeddings,
      documents: documents,
      min_topic_size: 2
    )
    
    expect(topics).not_to be_empty
    topics.each do |topic|
      expect(topic.terms).not_to be_empty
      expect(topic.documents).not_to be_empty
    end
  end
end
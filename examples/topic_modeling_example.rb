#!/usr/bin/env ruby

require_relative '../lib/ragnar'

# Generate some synthetic data for testing
documents = [
  # Machine learning cluster
  "Machine learning algorithms can be used to predict outcomes based on historical data. Deep learning is a subset of ML.",
  "Neural networks are powerful tools for pattern recognition. They can learn complex representations from data.",
  "Supervised learning requires labeled data for training. Common algorithms include SVM and random forests.",
  "Deep learning has revolutionized computer vision and natural language processing tasks.",
  "Gradient descent is used to optimize neural network parameters during training.",
  
  # Ruby programming cluster
  "Ruby is a dynamic programming language with a focus on simplicity and productivity.",
  "Rails is a web framework written in Ruby that follows the MVC pattern.",
  "Ruby gems are packages that extend the functionality of Ruby applications.",
  "The Ruby community values convention over configuration and developer happiness.",
  "Duck typing in Ruby allows for flexible and dynamic programming patterns.",
  
  # Data processing cluster
  "Data pipelines help automate the flow of data from source to destination.",
  "ETL processes extract, transform, and load data for analytics and reporting.",
  "Real-time data streaming enables immediate processing of incoming data.",
  "Data quality is crucial for accurate analytics and decision making.",
  "Batch processing is useful for handling large volumes of data efficiently.",
  
  # Cloud computing cluster
  "Cloud services provide scalable infrastructure without physical hardware management.",
  "Kubernetes orchestrates containerized applications across clusters of machines.",
  "Serverless computing allows developers to run code without managing servers.",
  "Cloud storage solutions offer redundancy and global accessibility.",
  "Infrastructure as code enables reproducible and version-controlled deployments.",
  
  # Testing and quality cluster
  "Unit tests verify individual components work correctly in isolation.",
  "Integration testing ensures different parts of the system work together.",
  "Test-driven development helps create better designed and more reliable code.",
  "Continuous integration automatically runs tests when code is committed.",
  "Code coverage metrics help identify untested parts of the codebase."
]

puts "Testing topic modeling with #{documents.length} synthetic documents..."

# Generate embeddings using the embedder
embedder = Ragnar::Embedder.new
print "Generating embeddings"
embeddings = embedder.embed_batch(documents, show_progress: false)
puts "\nGenerated #{embeddings.length} embeddings"

# Test topic extraction with different methods
[:fast, :hybrid].each do |method|
  puts "\n" + "="*60
  puts "Testing with method: #{method}"
  puts "="*60
  
  engine = Ragnar::TopicModeling::Engine.new(
    min_cluster_size: 2,  # Small value for test data
    min_samples: 1,       # Small value for test data
    labeling_method: method,
    verbose: true,
    reduce_dimensions: false  # Skip UMAP for now
  )
  
  topics = engine.fit(
    embeddings: embeddings,
    documents: documents
  )
  
  puts "\nResults:"
  topics.each_with_index do |topic, idx|
    puts "\nTopic #{idx + 1}: #{topic.label}"
    puts "  Size: #{topic.size} documents"
    puts "  Terms: #{topic.terms.first(5).join(', ')}"
    puts "  Sample: #{topic.representative_docs(k: 1).first[0..100]}..."
  end
  
  if topics.empty?
    puts "No topics found (all points may be outliers)"
  end
end

puts "\n" + "="*60
puts "Topic modeling test complete!"
# Topic Modeling Example

This example demonstrates how to use Ragnar's topic modeling capabilities with a sufficient number of documents for meaningful clustering.

## Ruby Code Example

```ruby
require 'ragnar'

# Create a diverse set of documents across multiple topics
# For effective clustering, we need at least 20-30 documents
documents = [
  # Finance/Economics Topic
  "The Federal Reserve raised interest rates to combat inflation pressures",
  "Stock markets rallied on positive earnings reports from tech companies",
  "Global supply chain disruptions continue to affect consumer prices",
  "Cryptocurrency markets experienced significant volatility this quarter",
  "Central banks coordinate policy to address economic uncertainty",
  "Corporate bond yields rise as investors seek safer assets",
  "Emerging markets face capital outflows amid dollar strength",

  # Technology/AI Topic
  "New AI breakthrough in natural language processing announced by researchers",
  "Machine learning transforms healthcare diagnostics and treatment planning",
  "Quantum computing reaches new milestone in error correction",
  "Open source community releases major updates to popular frameworks",
  "Cloud computing adoption accelerates across enterprise sectors",
  "Cybersecurity threats evolve with sophisticated ransomware attacks",
  "Artificial intelligence ethics guidelines proposed by tech consortium",

  # Healthcare/Medical Topic
  "Clinical trials show promising results for new cancer immunotherapy",
  "Telemedicine adoption continues to reshape patient care delivery",
  "Gene editing techniques advance treatment for rare diseases",
  "Mental health awareness campaigns gain momentum globally",
  "Vaccine development accelerates using mRNA technology platforms",
  "Healthcare systems invest in digital transformation initiatives",
  "Personalized medicine approaches show improved patient outcomes",

  # Climate/Environment Topic
  "Renewable energy investments surpass fossil fuel spending globally",
  "Climate scientists warn of accelerating Arctic ice melt",
  "Carbon capture technology receives significant government funding",
  "Sustainable agriculture practices reduce environmental impact",
  "Electric vehicle adoption reaches record levels worldwide",
  "Ocean conservation efforts expand marine protected areas",
  "Green hydrogen emerges as key solution for industrial decarbonization",

  # Sports Topic
  "Championship team breaks decades-old winning streak record",
  "Olympic athletes prepare for upcoming international competition",
  "Sports analytics revolutionize player performance evaluation",
  "Major league implements new rules to improve game pace",
  "Youth sports participation increases following pandemic recovery",
  "Stadium technology enhances fan experience with augmented reality",
  "Professional athletes advocate for mental health support",

  # Education Topic
  "Online learning platforms expand access to quality education globally",
  "Universities adopt hybrid teaching models post-pandemic",
  "STEM education initiatives target underrepresented communities",
  "Educational technology startups receive record venture funding",
  "Student debt relief programs gain political support",
  "Coding bootcamps address technology skills gap in workforce",
  "Research universities collaborate on climate change solutions"
]

# Initialize the indexer
indexer = Ragnar::Indexer.new(
  db_path: "topic_modeling.lance",
  chunk_size: 500,  # Each document becomes one chunk since they're short
  show_progress: true
)

# Index all documents
documents.each_with_index do |doc, idx|
  indexer.index_text(doc, {
    document_id: idx,
    source: "example_dataset"
  })
end

# Load documents with embeddings from database
database = Ragnar::Database.new("topic_modeling.lance")
all_docs = database.get_all_documents_with_embeddings

# Extract embeddings and texts
embeddings = all_docs.map { |doc| doc[:embedding] }
texts = all_docs.map { |doc| doc[:chunk_text] }

# Perform topic modeling using Topical
topics = Topical.extract(
  embeddings: embeddings,
  documents: texts,
  min_topic_size: 3,      # Minimum documents per topic
  min_samples: 2,         # HDBSCAN parameter for density
  cluster_selection_method: 'eom'  # Use EOM for better small clusters
)

# Display results
puts "\n=== Topic Modeling Results ==="
puts "Found #{topics.size} topics\n\n"

topics.each_with_index do |topic, idx|
  puts "Topic #{idx + 1}: #{topic.label || 'Unlabeled'}"
  puts "Size: #{topic.size} documents"
  puts "Key terms: #{topic.terms.take(10).join(', ')}"
  puts "Sample documents:"
  topic.documents.take(3).each do |doc|
    puts "  - #{doc[0..100]}..."
  end

  # Calculate and display metrics if available
  if defined?(topic.coherence_score)
    puts "Coherence score: #{topic.coherence_score.round(3)}"
  end

  puts "\n" + "-"*50 + "\n"
end

# Optional: Export for visualization
File.write('topics.json', topics.map(&:to_h).to_json)
puts "Topics exported to topics.json for visualization"
```

## Alternative: Generate Synthetic Documents

If you need more documents for testing, here's a helper to generate synthetic data:

```ruby
def generate_synthetic_documents(topics_config, docs_per_topic: 10)
  documents = []

  topics_config = {
    finance: {
      terms: %w[market stock investment portfolio trading earnings dividend yield bond equity],
      templates: [
        "The {term1} showed strong {term2} performance in today's trading session",
        "Analysts predict {term1} will impact {term2} in the coming quarter",
        "Investors are watching {term1} closely as {term2} trends emerge"
      ]
    },
    technology: {
      terms: %w[AI machine learning algorithm software cloud computing data neural network],
      templates: [
        "New {term1} breakthrough advances {term2} capabilities significantly",
        "Companies adopt {term1} to improve {term2} efficiency",
        "Research in {term1} shows promise for {term2} applications"
      ]
    },
    healthcare: {
      terms: %w[treatment patient clinical trial therapy diagnosis medical research drug vaccine],
      templates: [
        "The {term1} showed positive results in {term2} studies",
        "Healthcare providers implement new {term1} for better {term2}",
        "Recent {term1} advances improve {term2} outcomes"
      ]
    }
  }

  topics_config.each do |topic, config|
    docs_per_topic.times do
      template = config[:templates].sample
      term1 = config[:terms].sample
      term2 = (config[:terms] - [term1]).sample

      doc = template.gsub('{term1}', term1).gsub('{term2}', term2)
      documents << doc
    end
  end

  documents.shuffle
end

# Generate 50 synthetic documents
synthetic_docs = generate_synthetic_documents({}, docs_per_topic: 17)
```

## Tips for Better Topic Modeling

1. **Document Count**: Aim for at least 20-30 documents, ideally 50+ for robust clustering
2. **Document Length**: Documents should be long enough to be meaningful (50+ words)
3. **Diversity**: Include diverse topics for clear cluster separation
4. **Preprocessing**: Consider removing stop words and normalizing text
5. **Parameters**:
   - `min_topic_size`: Start with 3-5 for small datasets
   - `min_samples`: Usually 2-3 for sparse data
   - `cluster_selection_method`: 'eom' works better for small datasets

## Visualization

After extracting topics, visualize them:

```bash
# Export to HTML visualization
ragnar topics --export html --output topics.html

# Or programmatically:
visualizer = Ragnar::TopicVisualizer.new(topics)
visualizer.export_html("topics.html")
```

The visualization will show:
- Topic clusters in 2D space
- Topic sizes as bubble sizes
- Key terms for each topic
- Document distribution across topics

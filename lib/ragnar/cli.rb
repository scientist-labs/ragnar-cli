module Ragnar
  class CLI < Thor
    desc "index PATH", "Index text files from PATH (file or directory)"
    option :db_path, type: :string, default: Ragnar::DEFAULT_DB_PATH, desc: "Path to Lance database"
    option :chunk_size, type: :numeric, default: Ragnar::DEFAULT_CHUNK_SIZE, desc: "Chunk size in tokens"
    option :chunk_overlap, type: :numeric, default: Ragnar::DEFAULT_CHUNK_OVERLAP, desc: "Chunk overlap in tokens"
    option :model, type: :string, default: Ragnar::DEFAULT_EMBEDDING_MODEL, desc: "Embedding model to use"
    def index(path)
      unless File.exist?(path)
        say "Error: Path does not exist: #{path}", :red
        exit 1
      end

      say "Indexing files from: #{path}", :green

      indexer = Indexer.new(
        db_path: options[:db_path],
        chunk_size: options[:chunk_size],
        chunk_overlap: options[:chunk_overlap],
        embedding_model: options[:model]
      )

      begin
        stats = indexer.index_path(path)
        say "\nIndexing complete!", :green
        say "Files processed: #{stats[:files_processed]}"
        say "Chunks created: #{stats[:chunks_created]}"
        say "Errors: #{stats[:errors]}" if stats[:errors] > 0
      rescue => e
        say "Error during indexing: #{e.message}", :red
        exit 1
      end
    end

    desc "train-umap", "Train UMAP model on existing embeddings"
    option :db_path, type: :string, default: Ragnar::DEFAULT_DB_PATH, desc: "Path to Lance database"
    option :n_components, type: :numeric, default: 50, desc: "Number of dimensions for reduction"
    option :n_neighbors, type: :numeric, default: 15, desc: "Number of neighbors for UMAP"
    option :min_dist, type: :numeric, default: 0.1, desc: "Minimum distance for UMAP"
    option :model_path, type: :string, default: "umap_model.bin", desc: "Path to save UMAP model"
    def train_umap
      say "Training UMAP model on embeddings...", :green

      processor = UmapProcessor.new(
        db_path: options[:db_path],
        model_path: options[:model_path]
      )

      begin
        stats = processor.train(
          n_components: options[:n_components],
          n_neighbors: options[:n_neighbors],
          min_dist: options[:min_dist]
        )

        say "\nUMAP training complete!", :green
        say "Embeddings processed: #{stats[:embeddings_count]}"
        say "Original dimensions: #{stats[:original_dims]}"
        say "Reduced dimensions: #{stats[:reduced_dims]}"
        say "Model saved to: #{options[:model_path]}"
      rescue => e
        say "Error during UMAP training: #{e.message}", :red
        exit 1
      end
    end

    desc "apply-umap", "Apply trained UMAP model to reduce embedding dimensions"
    option :db_path, type: :string, default: Ragnar::DEFAULT_DB_PATH, desc: "Path to Lance database"
    option :model_path, type: :string, default: "umap_model.bin", desc: "Path to UMAP model"
    option :batch_size, type: :numeric, default: 100, desc: "Batch size for processing"
    def apply_umap
      unless File.exist?(options[:model_path])
        say "Error: UMAP model not found at: #{options[:model_path]}", :red
        say "Please run 'train-umap' first to create a model.", :yellow
        exit 1
      end

      say "Applying UMAP model to embeddings...", :green

      processor = UmapProcessor.new(
        db_path: options[:db_path],
        model_path: options[:model_path]
      )

      begin
        stats = processor.apply(batch_size: options[:batch_size])

        say "\nUMAP application complete!", :green
        say "Embeddings processed: #{stats[:processed]}"
        say "Already processed: #{stats[:skipped]}"
        say "Errors: #{stats[:errors]}" if stats[:errors] > 0
      rescue => e
        say "Error applying UMAP: #{e.message}", :red
        exit 1
      end
    end

    desc "topics", "Extract and display topics from indexed documents"
    option :db_path, type: :string, default: Ragnar::DEFAULT_DB_PATH, desc: "Path to Lance database"
    option :min_cluster_size, type: :numeric, default: 5, desc: "Minimum documents per topic"
    option :method, type: :string, default: "hybrid", desc: "Labeling method: fast, quality, or hybrid"
    option :export, type: :string, desc: "Export topics to file (json or html)"
    option :verbose, type: :boolean, default: false, aliases: "-v", desc: "Show detailed processing"
    def topics
      require_relative 'topic_modeling'

      say "Extracting topics from indexed documents...", :green

      # Load embeddings and documents from database
      database = Database.new(options[:db_path])

      begin
        # Get all documents with embeddings
        stats = database.get_stats
        if stats[:with_embeddings] == 0
          say "No documents with embeddings found. Please index some documents first.", :red
          exit 1
        end

        say "Loading #{stats[:with_embeddings]} documents...", :yellow

        # Get all documents with embeddings
        docs_with_embeddings = database.get_all_documents_with_embeddings

        if docs_with_embeddings.empty?
          say "Could not load documents from database. Please check your database.", :red
          exit 1
        end

        embeddings = docs_with_embeddings.map { |d| d[:embedding] }
        documents = docs_with_embeddings.map { |d| d[:chunk_text] }
        metadata = docs_with_embeddings.map { |d| { file_path: d[:file_path], chunk_index: d[:chunk_index] } }

        say "Loaded #{embeddings.length} embeddings and #{documents.length} documents", :yellow if options[:verbose]

        # Initialize topic modeling engine
        engine = Ragnar::TopicModeling::Engine.new(
          min_cluster_size: options[:min_cluster_size],
          labeling_method: options[:method].to_sym,
          verbose: options[:verbose]
        )

        # Extract topics
        say "Clustering documents...", :yellow
        topics = engine.fit(
          embeddings: embeddings,
          documents: documents,
          metadata: metadata
        )

        # Display results
        display_topics(topics)

        # Export if requested
        if options[:export]
          export_topics(topics, options[:export])
        end

      rescue => e
        say "Error extracting topics: #{e.message}", :red
        say e.backtrace.first(5).join("\n") if options[:verbose]
        exit 1
      end
    end

    desc "search QUERY", "Search for similar documents"
    option :database, type: :string, default: Ragnar::DEFAULT_DB_PATH, aliases: "-d", desc: "Path to Lance database"
    option :k, type: :numeric, default: 5, desc: "Number of results to return"
    option :show_scores, type: :boolean, default: false, desc: "Show similarity scores"
    def search(query_text)
      database = Database.new(options[:database])
      embedder = Embedder.new
      
      # Generate embedding for query
      query_embedding = embedder.embed_text(query_text)
      
      # Search for similar documents
      results = database.search_similar(query_embedding, k: options[:k])
      
      if results.empty?
        say "No results found.", :yellow
        return
      end
      
      say "Found #{results.length} results:\n", :green
      
      results.each_with_index do |result, idx|
        say "#{idx + 1}. File: #{result[:file_path]}", :cyan
        say "   Chunk: #{result[:chunk_index]}"
        
        if options[:show_scores]
          say "   Distance: #{result[:distance].round(4)}"
        end
        
        # Show preview of content
        preview = result[:chunk_text][0..200].gsub(/\s+/, ' ')
        say "   Content: #{preview}..."
        say ""
      end
    end
    
    desc "query QUESTION", "Query the RAG system"
    option :db_path, type: :string, default: Ragnar::DEFAULT_DB_PATH, desc: "Path to Lance database"
    option :top_k, type: :numeric, default: 3, desc: "Number of top documents to use"
    option :verbose, type: :boolean, default: false, aliases: "-v", desc: "Show detailed processing steps"
    option :json, type: :boolean, default: false, desc: "Output as JSON"
    def query(question)
      processor = QueryProcessor.new(db_path: options[:db_path])

      begin
        result = processor.query(question, top_k: options[:top_k], verbose: options[:verbose])

        if options[:json]
          puts JSON.pretty_generate(result)
        else
          say "\n" + "="*60, :green
          say "Query: #{result[:query]}", :cyan

          if result[:clarified] != result[:query]
            say "Clarified: #{result[:clarified]}", :yellow
          end

          say "\nAnswer:", :green
          say result[:answer]

          if result[:confidence]
            say "\nConfidence: #{result[:confidence]}%", :magenta
          end

          if result[:sources] && !result[:sources].empty?
            say "\nSources:", :blue
            result[:sources].each_with_index do |source, idx|
              say "  #{idx + 1}. #{source[:source_file]}" if source[:source_file]
            end
          end

          if options[:verbose] && result[:sub_queries]
            say "\nSub-queries used:", :yellow
            result[:sub_queries].each { |sq| say "  - #{sq}" }
          end

          say "="*60, :green
        end
      rescue => e
        say "Error processing query: #{e.message}", :red
        say e.backtrace.first(5).join("\n") if options[:verbose]
        exit 1
      end
    end

    desc "stats", "Show database statistics"
    option :db_path, type: :string, default: Ragnar::DEFAULT_DB_PATH, desc: "Path to Lance database"
    def stats
      db = Database.new(options[:db_path])
      stats = db.get_stats

      say "\nDatabase Statistics", :green
      say "-" * 30
      say "Total documents: #{stats[:total_documents]}"
      say "Unique files: #{stats[:unique_files]}"
      say "Total chunks: #{stats[:total_chunks]}"
      say "With embeddings: #{stats[:with_embeddings]}"
      say "With reduced embeddings: #{stats[:with_reduced_embeddings]}"

      if stats[:total_chunks] > 0
        say "\nAverage chunk size: #{stats[:avg_chunk_size]} characters"
        say "Embedding dimensions: #{stats[:embedding_dims]}"
        say "Reduced dimensions: #{stats[:reduced_dims]}" if stats[:reduced_dims]
      end
    rescue => e
      say "Error reading database: #{e.message}", :red
      exit 1
    end

    desc "version", "Show version"
    def version
      say "Ragnar v#{Ragnar::VERSION}"
    end

    private

    def fetch_all_documents(database)
      # Temporary workaround to get all documents
      # In production, we'd add a proper method to Database class
      # For now, do a large search to get all docs

      # Get stats to determine embedding size
      stats = database.get_stats
      embedding_dims = stats[:embedding_dims] || 768

      # Generate a dummy embedding to search with
      dummy_embedding = Array.new(embedding_dims, 0.0)

      # Search for a large number to get all docs
      results = database.search_similar(dummy_embedding, k: 10000)

      # Return all results that have valid embeddings and text
      results.select do |r|
        r[:embedding] && !r[:embedding].empty? &&
        r[:chunk_text] && !r[:chunk_text].empty?
      end
    rescue => e
      say "Error loading documents: #{e.message}", :red
      say e.backtrace.first(3).join("\n") if options[:verbose]
      []
    end

    def display_topics(topics)
      say "\n" + "="*60, :green
      say "Topic Analysis Results", :cyan
      say "="*60, :green

      if topics.empty?
        say "No topics found. Try adjusting min_cluster_size.", :yellow
        return
      end

      say "\nFound #{topics.length} topics:", :green

      # Group topics by size for better visualization
      large_topics = topics.select { |t| t.size >= 20 }
      medium_topics = topics.select { |t| t.size >= 10 && t.size < 20 }
      small_topics = topics.select { |t| t.size < 10 }

      if large_topics.any?
        say "\n" + "─" * 40, :blue
        say "MAJOR TOPICS (≥20 docs)", :blue
        say "─" * 40, :blue
        display_topic_group(large_topics, :cyan)
      end

      if medium_topics.any?
        say "\n" + "─" * 40, :yellow
        say "MEDIUM TOPICS (10-19 docs)", :yellow
        say "─" * 40, :yellow
        display_topic_group(medium_topics, :yellow)
      end

      if small_topics.any?
        say "\n" + "─" * 40, :white
        say "MINOR TOPICS (<10 docs)", :white
        say "─" * 40, :white
        display_topic_group(small_topics, :white)
      end

      # Summary statistics
      total_docs = topics.sum(&:size)
      say "\n" + "="*60, :green
      say "SUMMARY STATISTICS", :green
      say "="*60, :green
      say "  Total topics: #{topics.length}"
      say "  Documents in topics: #{total_docs}"
      say "  Average topic size: #{(total_docs.to_f / topics.length).round(1)}"

      if topics.any? { |t| t.coherence > 0 }
        avg_coherence = topics.map(&:coherence).sum / topics.length
        say "  Average coherence: #{(avg_coherence * 100).round(1)}%"
      end

      # Distribution breakdown
      say "\n  Size distribution:"
      say "    Large (≥20): #{large_topics.length} topics, #{large_topics.sum(&:size)} docs"
      say "    Medium (10-19): #{medium_topics.length} topics, #{medium_topics.sum(&:size)} docs"
      say "    Small (<10): #{small_topics.length} topics, #{small_topics.sum(&:size)} docs"
    end

    def display_topic_group(topics, color)
      topics.sort_by { |t| -t.size }.each_with_index do |topic, idx|
        say "\n#{topic.label || 'Unlabeled'} (#{topic.size} docs)", color

        # Show coherence as a bar
        if topic.coherence > 0
          coherence_pct = (topic.coherence * 100).round(0)
          bar_length = (coherence_pct / 5).to_i
          bar = "█" * bar_length + "░" * (20 - bar_length)
          say "  Coherence: #{bar} #{coherence_pct}%"
        end

        # Compact term display
        say "  Terms: #{topic.terms.first(6).join(' • ')}" if topic.terms.any?

        # Short sample
        if topic.representative_docs(k: 1).any?
          preview = topic.representative_docs(k: 1).first
          preview = preview[0..100] + "..." if preview.length > 100
          say "  \"#{preview}\"", :white
        end
      end
    end

    def export_topics(topics, format)
      case format.downcase
      when 'json'
        export_topics_json(topics)
      when 'html'
        export_topics_html(topics)
      else
        say "Unknown export format: #{format}. Use 'json' or 'html'.", :red
      end
    end

    def export_topics_json(topics)
      data = {
        generated_at: Time.now.iso8601,
        topics: topics.map(&:to_h),
        summary: {
          total_topics: topics.length,
          total_documents: topics.sum(&:size),
          average_size: (topics.sum(&:size).to_f / topics.length).round(1)
        }
      }

      filename = "topics_#{Time.now.strftime('%Y%m%d_%H%M%S')}.json"
      File.write(filename, JSON.pretty_generate(data))
      say "Topics exported to: #{filename}", :green
    end

    def export_topics_html(topics)
      # Generate self-contained HTML with D3.js visualization
      html = generate_topic_visualization_html(topics)

      filename = "topics_#{Time.now.strftime('%Y%m%d_%H%M%S')}.html"
      File.write(filename, html)
      say "Topics visualization exported to: #{filename}", :green

      # Offer to open in browser
      if yes?("Open in browser?")
        system("open #{filename}") rescue nil  # macOS
        system("xdg-open #{filename}") rescue nil  # Linux
      end
    end

    def generate_topic_visualization_html(topics)
      # Convert topics to JSON for D3.js
      topics_json = topics.map do |topic|
        {
          id: topic.id,
          label: topic.label || "Topic #{topic.id}",
          size: topic.size,
          terms: topic.terms.first(10),
          coherence: topic.coherence,
          samples: topic.representative_docs(k: 2).map { |d| d[0..200] }
        }
      end.to_json

      # HTML template with embedded D3.js
      <<~HTML
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <title>Topic Visualization</title>
          <script src="https://d3js.org/d3.v7.min.js"></script>
          <style>
            body { font-family: -apple-system, sans-serif; margin: 20px; }
            #viz { width: 100%; height: 500px; border: 1px solid #ddd; }
            .topic { cursor: pointer; }
            .topic:hover { opacity: 0.8; }
            #details { margin-top: 20px; padding: 15px; background: #f5f5f5; }
            .term { display: inline-block; margin: 5px; padding: 5px 10px; background: #e0e0e0; border-radius: 3px; }
          </style>
        </head>
        <body>
          <h1>Topic Analysis Results</h1>
          <div id="viz"></div>
          <div id="details">Click on a topic to see details</div>

          <script>
            const data = #{topics_json};

            // Create bubble chart
            const width = document.getElementById('viz').clientWidth;
            const height = 500;

            const svg = d3.select("#viz")
              .append("svg")
              .attr("width", width)
              .attr("height", height);

            // Create scale for bubble sizes
            const sizeScale = d3.scaleSqrt()
              .domain([0, d3.max(data, d => d.size)])
              .range([10, 50]);

            // Create color scale
            const colorScale = d3.scaleSequential(d3.interpolateViridis)
              .domain([0, 1]);

            // Create force simulation
            const simulation = d3.forceSimulation(data)
              .force("x", d3.forceX(width / 2).strength(0.05))
              .force("y", d3.forceY(height / 2).strength(0.05))
              .force("collide", d3.forceCollide(d => sizeScale(d.size) + 2));

            // Create bubbles
            const bubbles = svg.selectAll(".topic")
              .data(data)
              .enter().append("g")
              .attr("class", "topic");

            bubbles.append("circle")
              .attr("r", d => sizeScale(d.size))
              .attr("fill", d => colorScale(d.coherence))
              .attr("stroke", "#fff")
              .attr("stroke-width", 2);

            bubbles.append("text")
              .text(d => d.label)
              .attr("text-anchor", "middle")
              .attr("dy", ".3em")
              .style("font-size", d => Math.min(sizeScale(d.size) / 3, 14) + "px");

            // Add click handler
            bubbles.on("click", function(event, d) {
              showDetails(d);
            });

            // Update positions
            simulation.on("tick", () => {
              bubbles.attr("transform", d => `translate(${d.x},${d.y})`);
            });

            // Show topic details
            function showDetails(topic) {
              const details = document.getElementById('details');
              details.innerHTML = `
                <h2>${topic.label}</h2>
                <p><strong>Documents:</strong> ${topic.size}</p>
                <p><strong>Coherence:</strong> ${(topic.coherence * 100).toFixed(1)}%</p>
                <p><strong>Top Terms:</strong></p>
                <div>${topic.terms.map(t => `<span class="term">${t}</span>`).join('')}</div>
                <p><strong>Sample Documents:</strong></p>
                ${topic.samples.map(s => `<p style="font-size: 0.9em; color: #666;">"${s}..."</p>`).join('')}
              `;
            }
          </script>
        </body>
        </html>
      HTML
    end
  end
end
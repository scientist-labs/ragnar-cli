require 'json'

module Ragnar
  module TopicModeling
    class Engine
      attr_reader :topics, :clusterer, :term_extractor
      
      def initialize(
        min_cluster_size: 5,
        min_samples: 3,
        clustering_backend: nil,
        reduce_dimensions: true,
        n_components: 50,
        labeling_method: :hybrid,
        llm_client: nil,
        verbose: false
      )
        @min_cluster_size = min_cluster_size
        @min_samples = min_samples
        @reduce_dimensions = reduce_dimensions
        @n_components = n_components
        @labeling_method = labeling_method
        @verbose = verbose
        
        @clusterer = clustering_backend || build_default_clusterer
        @term_extractor = TermExtractor.new
        @labeler = TopicLabeler.new(method: labeling_method, llm_client: llm_client)
        @topics = []
      end
      
      def fit(embeddings:, documents:, metadata: nil)
        raise ArgumentError, "Embeddings and documents must have same length" unless embeddings.length == documents.length
        
        @embeddings = embeddings
        @documents = documents
        @metadata = metadata || Array.new(documents.length) { {} }
        
        puts "Starting topic extraction..." if @verbose
        
        # Step 1: Optionally reduce dimensions for better clustering
        working_embeddings = @embeddings
        if @reduce_dimensions && @embeddings.first.length > @n_components
          puts "  Reducing dimensions from #{@embeddings.first.length} to #{@n_components}..." if @verbose
          working_embeddings = reduce_dimensions(@embeddings)
        end
        
        # Step 2: Cluster embeddings
        puts "  Clustering #{working_embeddings.length} documents..." if @verbose
        cluster_ids = @clusterer.fit_predict(working_embeddings)
        
        # Step 3: Build topics from clusters
        puts "  Building topics..." if @verbose
        @topics = build_topics(cluster_ids)
        
        # Step 4: Extract terms for each topic
        puts "  Extracting distinctive terms..." if @verbose
        extract_topic_terms
        
        # Step 5: Generate labels
        puts "  Generating topic labels..." if @verbose
        generate_topic_labels
        
        puts "Found #{@topics.length} topics (plus #{count_outliers(cluster_ids)} outliers)" if @verbose
        
        @topics
      end
      
      def transform(embeddings:, documents: nil)
        # Assign new documents to existing topics
        raise "Must call fit before transform" if @topics.empty?
        
        # Use approximate prediction if available
        if @clusterer.respond_to?(:approximate_predict)
          @clusterer.approximate_predict(embeddings)
        else
          # Fallback: assign to nearest topic centroid
          assign_to_nearest_topic(embeddings)
        end
      end
      
      def get_topic(topic_id)
        @topics.find { |t| t.id == topic_id }
      end
      
      def outliers
        @outliers ||= @documents.each_with_index.select { |_, idx| 
          @cluster_ids && @cluster_ids[idx] == -1 
        }.map(&:first)
      end
      
      def save(path)
        data = {
          topics: @topics.map(&:to_h),
          config: {
            min_cluster_size: @min_cluster_size,
            min_samples: @min_samples,
            reduce_dimensions: @reduce_dimensions,
            n_components: @n_components,
            labeling_method: @labeling_method
          }
        }
        File.write(path, JSON.pretty_generate(data))
      end
      
      def self.load(path)
        data = JSON.parse(File.read(path), symbolize_names: true)
        engine = new(**data[:config])
        # Reconstruct topics
        engine.instance_variable_set(:@topics, data[:topics].map { |t| Topic.from_h(t) })
        engine
      end
      
      private
      
      def build_default_clusterer
        begin
          require 'clusterkit'
          ClusterKit::Clustering::HDBSCAN.new(
            min_cluster_size: @min_cluster_size,
            min_samples: @min_samples,
            metric: 'euclidean'
          )
        rescue LoadError
          raise "ClusterKit required for topic modeling. Add 'gem \"clusterkit\"' to your Gemfile."
        end
      end
      
      def reduce_dimensions(embeddings)
        require 'clusterkit'
        
        umap = ClusterKit::Dimensionality::UMAP.new(
          n_components: @n_components,
          n_neighbors: 15,
          random_seed: 42  # For reproducibility
        )
        
        # Convert to format UMAP expects
        umap.fit_transform(embeddings)
      rescue LoadError
        puts "Warning: Dimensionality reduction requires ClusterKit. Using original embeddings." if @verbose
        embeddings
      end
      
      def build_topics(cluster_ids)
        @cluster_ids = cluster_ids
        
        # Group documents by cluster
        clusters = {}
        cluster_ids.each_with_index do |cluster_id, doc_idx|
          next if cluster_id == -1  # Skip outliers
          clusters[cluster_id] ||= []
          clusters[cluster_id] << doc_idx
        end
        
        # Create Topic objects
        clusters.map do |cluster_id, doc_indices|
          Topic.new(
            id: cluster_id,
            document_indices: doc_indices,
            documents: doc_indices.map { |i| @documents[i] },
            embeddings: doc_indices.map { |i| @embeddings[i] },
            metadata: doc_indices.map { |i| @metadata[i] }
          )
        end.sort_by(&:id)
      end
      
      def extract_topic_terms
        # Extract distinctive terms for each topic
        all_docs_text = @documents.join(" ")
        
        @topics.each do |topic|
          topic_docs_text = topic.documents.join(" ")
          
          # Use c-TF-IDF to find distinctive terms
          terms = @term_extractor.extract_distinctive_terms(
            topic_docs: topic.documents,
            all_docs: @documents,
            top_n: 20
          )
          
          topic.set_terms(terms)
        end
      end
      
      def generate_topic_labels
        @topics.each do |topic|
          result = @labeler.generate_label(
            topic: topic,
            terms: topic.terms,
            documents: topic.documents.first(3)  # Use top 3 representative docs
          )
          
          # Set both label and description if available
          topic.set_label(result[:label])
          topic.instance_variable_set(:@description, result[:description]) if result[:description]
          topic.instance_variable_set(:@label_confidence, result[:confidence])
          topic.instance_variable_set(:@themes, result[:themes]) if result[:themes]
        end
      end
      
      def count_outliers(cluster_ids)
        cluster_ids.count { |id| id == -1 }
      end
      
      def assign_to_nearest_topic(embeddings)
        # Simple nearest centroid assignment
        topic_centroids = @topics.map(&:centroid)
        
        embeddings.map do |embedding|
          distances = topic_centroids.map do |centroid|
            # Euclidean distance
            Math.sqrt(embedding.zip(centroid).map { |a, b| (a - b) ** 2 }.sum)
          end
          
          min_idx = distances.index(distances.min)
          @topics[min_idx].id
        end
      end
    end
  end
end
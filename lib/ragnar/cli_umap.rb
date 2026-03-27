# frozen_string_literal: true

require "thor"

module Ragnar
  class CLI < Thor
    class Umap < Thor
      desc "train", "Train UMAP model on existing embeddings"
      option :db_path, type: :string, desc: "Path to Lance database (default from config)"
      option :n_components, type: :numeric, default: 50, desc: "Number of dimensions for reduction"
      option :n_neighbors, type: :numeric, default: 15, desc: "Number of neighbors for UMAP"
      option :min_dist, type: :numeric, default: 0.1, desc: "Minimum distance for UMAP"
      option :model_path, type: :string, desc: "Path to save UMAP model"
      def train
        say "Training UMAP model on embeddings...", :green

        config = Config.instance
        model_path = if options[:model_path]
          options[:model_path]
        else
          File.join(config.models_dir, "umap_model.bin")
        end

        processor = UmapProcessor.new(
          db_path: options[:db_path] || config.database_path,
          model_path: model_path
        )

        begin
          stats = processor.train(
            n_components: options[:n_components] || 50,
            n_neighbors: options[:n_neighbors] || 15,
            min_dist: options[:min_dist] || 0.1
          )

          say "\nUMAP training complete!", :green
          say "Embeddings processed: #{stats[:embeddings_count]}"
          say "Original dimensions: #{stats[:original_dims]}"
          say "Reduced dimensions: #{stats[:reduced_dims]}"
          say "Model saved to: #{processor.model_path}"
        rescue => e
          say "Error during UMAP training: #{e.message}", :red
          exit 1
        end
      end

      desc "apply", "Apply trained UMAP model to reduce embedding dimensions"
      option :db_path, type: :string, desc: "Path to Lance database (default from config)"
      option :model_path, type: :string, desc: "Path to UMAP model"
      option :batch_size, type: :numeric, default: 100, desc: "Batch size for processing"
      def apply
        config = Config.instance
        model_path = if options[:model_path]
          options[:model_path]
        else
          File.join(config.models_dir, "umap_model.bin")
        end

        unless File.exist?(model_path)
          say "Error: UMAP model not found at: #{model_path}", :red
          say "Please run 'ragnar umap train' first to create a model.", :yellow
          exit 1
        end

        say "Applying UMAP model to embeddings...", :green

        processor = UmapProcessor.new(
          db_path: options[:db_path] || config.database_path,
          model_path: model_path
        )

        begin
          stats = processor.apply(batch_size: options[:batch_size] || 100)

          say "\nUMAP application complete!", :green
          say "Embeddings processed: #{stats[:processed]}"
          say "Already processed: #{stats[:skipped]}"
          say "Errors: #{stats[:errors]}" if stats[:errors] > 0
        rescue => e
          say "Error applying UMAP: #{e.message}", :red
          exit 1
        end
      end
    end
  end
end

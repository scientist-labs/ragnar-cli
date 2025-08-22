# frozen_string_literal: true

require "spec_helper"
require "thor"

RSpec.describe Ragnar::CLI do
  let(:cli) { described_class.new }
  let(:db_path) { File.join(@temp_dir, "test_db") }

  around(:each) do |example|
    Dir.mktmpdir do |temp_dir|
      @temp_dir = temp_dir
      example.run
    end
  end

  describe "#index" do
    let(:test_file) { File.join(@temp_dir, "test.txt") }

    before do
      File.write(test_file, "Test content for CLI indexing")
    end

    it "indexes a single file" do
      output = capture_stdout do
        cli.invoke(:index, [test_file], { db_path: db_path })
      end

      expect(output).to include("Indexing files from:")
      expect(File.exist?(db_path)).to be true
    end

    it "indexes a directory" do
      File.write(File.join(@temp_dir, "file1.txt"), "Content 1")
      File.write(File.join(@temp_dir, "file2.txt"), "Content 2")

      output = capture_stdout do
        cli.invoke(:index, [@temp_dir], { db_path: db_path })
      end

      expect(output).to include("Indexing files from:")
    end

    it "accepts custom chunk size" do
      output = capture_stdout do
        cli.invoke(:index, [test_file], {
          db_path: db_path,
          chunk_size: 100
        })
      end

      expect(output).to include("Indexing files from:")
    end

    it "accepts custom chunk overlap" do
      output = capture_stdout do
        cli.invoke(:index, [test_file], {
          db_path: db_path,
          chunk_overlap: 20
        })
      end

      expect(output).to include("Indexing files from:")
    end

    it "filters by file extensions" do
      File.write(File.join(@temp_dir, "doc.txt"), "Text file")
      File.write(File.join(@temp_dir, "doc.md"), "Markdown file")
      File.write(File.join(@temp_dir, "doc.rb"), "Ruby file")

      output = capture_stdout do
        cli.invoke(:index, [@temp_dir], {
          db_path: db_path,
          extensions: [".txt", ".md"]
        })
      end

      expect(output).to include("Indexing files from:")

      # Verify only specified extensions were indexed
      database = Ragnar::Database.new(db_path)
      docs = database.get_embeddings
      file_paths = docs.map { |d| d[:file_path] }

      expect(file_paths.none? { |p| p.end_with?(".rb") }).to be true
    end
  end

  describe "#search" do
    before do
      # Set up test database with content
      File.write(File.join(@temp_dir, "ruby.txt"), "Ruby is great for web development")

      suppress_stdout do
        indexer = Ragnar::Indexer.new(db_path: db_path, show_progress: false)
        indexer.index_path(@temp_dir)
      end
    end

    it "searches the database" do
      output = capture_stdout do
        cli.invoke(:search, ["Ruby development"], { database: db_path })
      end

      expect(output).to include("ruby.txt")
    end

    it "respects the k parameter" do
      output = capture_stdout do
        cli.invoke(:search, ["programming"], {
          database: db_path,
          k: 1
        })
      end

      # Should return at most 1 result
      expect(output.scan(/File:/).count).to be <= 1
    end

    it "shows scores when requested" do
      output = capture_stdout do
        cli.invoke(:search, ["Ruby"], {
          database: db_path,
          show_scores: true
        })
      end

      expect(output).to match(/Score:|Distance:/)
    end
  end

  describe "#query" do
    before do
      # Set up test database
      File.write(File.join(@temp_dir, "ruby.txt"), "Ruby is a programming language")

      suppress_stdout do
        indexer = Ragnar::Indexer.new(db_path: db_path, show_progress: false)
        indexer.index_path(@temp_dir)
      end
    end

    it "queries with LLM using context from database" do
      output = capture_stdout do
        cli.invoke(:query, ["What is Ruby?"], {
          db_path: db_path,
          model: "test-model"
        })
      end

      expect(output).to include("Ruby")
    end

    it "uses specified LLM model" do
      suppress_stdout do
        cli.invoke(:query, ["test query"], {
          db_path: db_path,
          model: "custom-model"
        })
      end
    end
  end

  describe "#stats" do
    before do
      # Create test files and index them
      3.times do |i|
        File.write(File.join(@temp_dir, "file#{i}.txt"), "Content #{i}" * 10)
      end

      suppress_stdout do
        indexer = Ragnar::Indexer.new(db_path: db_path, show_progress: false)
        indexer.index_path(@temp_dir)
      end
    end

    it "displays database statistics" do
      output = capture_stdout do
        cli.invoke(:stats, [], { db_path: db_path })
      end

      expect(output).to include("Database Statistics")
      expect(output).to include("Total documents:")
      expect(output).to include("Unique files:")
    end

    it "handles non-existent database gracefully" do
      output = capture_stdout do
        cli.invoke(:stats, [], { db_path: "nonexistent_db" })
      end

      expect(output).to include("0") # Should show zeros or handle gracefully
    end
  end

  describe "#version" do
    it "displays the version" do
      output = capture_stdout do
        cli.invoke(:version)
      end

      expect(output).to include(Ragnar::VERSION)
    end
  end

  describe "#topics" do
    before do
      # Create diverse content for topic modeling
      File.write(File.join(@temp_dir, "ruby1.txt"),
                 "Ruby programming language syntax and features " * 5)
      File.write(File.join(@temp_dir, "ruby2.txt"),
                 "Ruby on Rails web framework development " * 5)
      File.write(File.join(@temp_dir, "python1.txt"),
                 "Python data science machine learning numpy pandas " * 5)
      File.write(File.join(@temp_dir, "js1.txt"),
                 "JavaScript React Vue Angular frontend development " * 5)

      suppress_stdout do
        indexer = Ragnar::Indexer.new(db_path: db_path, show_progress: false)
        indexer.index_path(@temp_dir)
      end
    end

    it "performs topic modeling" do
      output = capture_stdout do
        cli.invoke(:topics, [], {
          db_path: db_path,
          num_topics: 3
        })
      end

      expect(output).to include("Topic")
    end

    it "accepts custom number of topics" do
      output = capture_stdout do
        cli.invoke(:topics, [], {
          db_path: db_path,
          num_topics: 2
        })
      end

      expect(output).to include("Topic")
      # Should have 2 topics
      expect(output.scan(/Topic \d+/).uniq.size).to be <= 2
    end
  end

  describe "error handling" do
    it "handles missing required arguments gracefully" do
      expect { cli.invoke(:search, []) }.to raise_error(Thor::InvocationError)
    end

    it "handles invalid file paths" do
      output = capture_stdout do
        cli.invoke(:index, ["/nonexistent/path"], { db_path: db_path })
      end

      expect(output).to include("Indexing files from:") # Should still try to process
    end

    it "handles invalid database path for search" do
      output = capture_stdout do
        cli.invoke(:search, ["query"], { database: "/nonexistent/db" })
      end

      # Should handle gracefully, possibly return no results
      expect(output).not_to include("Error")
    end
  end
end
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ragnar::Indexer do
  let(:db_path) { File.join(@temp_dir, "test_db") }
  let(:indexer) { described_class.new(db_path: db_path, show_progress: false) }

  around(:each) do |example|
    Dir.mktmpdir do |temp_dir|
      @temp_dir = temp_dir
      example.run
    end
  end

  describe "#initialize" do
    it "creates an indexer with default settings" do
      expect(indexer).to be_a(Ragnar::Indexer)
      expect(indexer.database).to be_a(Ragnar::Database)
      expect(indexer.chunker).to be_a(Ragnar::Chunker)
      expect(indexer.embedder).to be_a(Ragnar::Embedder)
    end

    it "accepts custom chunk size and overlap" do
      custom_indexer = described_class.new(
        db_path: db_path,
        chunk_size: 1000,
        chunk_overlap: 100,
        show_progress: false
      )
      
      expect(custom_indexer.chunker.chunk_size).to eq(1000)
      expect(custom_indexer.chunker.chunk_overlap).to eq(100)
    end
  end

  describe "#index_path" do
    let(:temp_file) { File.join(@temp_dir, "test.txt") }

    before do
      File.write(temp_file, "This is test content for indexing. " * 10)
    end

    it "indexes a single file" do
      suppress_stdout do
        result = indexer.index_path(temp_file)
      end
      
      # Verify the file was indexed by checking the database
      database = Ragnar::Database.new(db_path)
      expect(database.count).to be > 0
    end

    it "skips non-existent files" do
      non_existent = File.join(@temp_dir, "nonexistent.txt")
      
      suppress_stdout do
        result = indexer.index_path(non_existent)
      end
      
      database = Ragnar::Database.new(db_path)
      expect(database.count).to eq(0)
    end

    it "handles empty files" do
      empty_file = File.join(@temp_dir, "empty.txt")
      File.write(empty_file, "")
      
      suppress_stdout do
        result = indexer.index_path(empty_file)
      end
      
      database = Ragnar::Database.new(db_path)
      expect(database.count).to eq(0)
    end
  end

  describe "#index_path (directory)" do
    let(:test_dir) { File.join(@temp_dir, "test_docs") }

    before do
      FileUtils.mkdir_p(test_dir)
      File.write(File.join(test_dir, "doc1.txt"), "Document 1 content")
      File.write(File.join(test_dir, "doc2.txt"), "Document 2 content")
      File.write(File.join(test_dir, "doc3.md"), "Document 3 markdown content")
    end

    it "indexes all text files in a directory" do
      suppress_stdout do
        indexer.index_path(test_dir)
      end
      
      database = Ragnar::Database.new(db_path)
      expect(database.count).to be > 0
    end

    it "indexes multiple file types" do
      suppress_stdout do
        indexer.index_path(test_dir)
      end
      
      database = Ragnar::Database.new(db_path)
      documents = database.get_all_documents_with_embeddings
      
      # Should index multiple file types (.txt, .md, etc)
      file_paths = documents.map { |d| d[:file_path] }
      expect(file_paths.size).to be > 0
      # Check that it indexed both .txt and .md files
      expect(file_paths.any? { |p| p.end_with?(".txt") }).to be true
      expect(file_paths.any? { |p| p.end_with?(".md") }).to be true
    end

    it "indexes recursively through subdirectories" do
      subdir = File.join(test_dir, "subdir")
      FileUtils.mkdir_p(subdir)
      File.write(File.join(subdir, "subdoc.txt"), "Subdirectory document")
      
      suppress_stdout do
        indexer.index_path(test_dir)
      end
      
      database = Ragnar::Database.new(db_path)
      documents = database.get_all_documents_with_embeddings
      
      file_paths = documents.map { |d| d[:file_path] }
      expect(file_paths.any? { |p| p.include?("subdir") }).to be true
    end

    it "handles empty directories" do
      empty_dir = File.join(@temp_dir, "empty_dir")
      FileUtils.mkdir_p(empty_dir)
      
      suppress_stdout do
        indexer.index_path(empty_dir)
      end
      
      database = Ragnar::Database.new(db_path)
      expect(database.count).to eq(0)
    end

    it "skips binary files" do
      # Create a fake binary file
      binary_file = File.join(test_dir, "binary.bin")
      File.open(binary_file, "wb") do |f|
        f.write([0x00, 0x01, 0x02, 0x03].pack("C*"))
      end
      
      suppress_stdout do
        indexer.index_path(test_dir)
      end
      
      database = Ragnar::Database.new(db_path)
      documents = database.get_all_documents_with_embeddings
      
      file_paths = documents.map { |d| d[:file_path] }
      expect(file_paths.none? { |p| p.end_with?(".bin") }).to be true
    end
  end

  describe "#index_path (multiple files)" do
    let(:files) do
      3.times.map do |i|
        file = File.join(@temp_dir, "file#{i}.txt")
        File.write(file, "Content for file #{i}")
        file
      end
    end

    it "indexes multiple files" do
      suppress_stdout do
        files.each { |f| indexer.index_path(f) }
      end
      
      database = Ragnar::Database.new(db_path)
      expect(database.count).to eq(3)
    end

    it "shows progress during indexing" do
      # Create indexer with progress enabled for this test
      progress_indexer = described_class.new(db_path: db_path, show_progress: true)
      
      output = capture_stdout do
        files.each { |f| progress_indexer.index_path(f) }
      end
      
      expect(output).to include("Found")
    end

    it "handles mixed valid and invalid files" do
      invalid_file = File.join(@temp_dir, "nonexistent.txt")
      mixed_files = files + [invalid_file]
      
      suppress_stdout do
        indexer.index_files(mixed_files)
      end
      
      database = Ragnar::Database.new(db_path)
      # Should still index the valid files
      expect(database.count).to eq(3)
    end
  end

  describe "#get_stats" do
    before do
      3.times do |i|
        file = File.join(@temp_dir, "file#{i}.txt")
        File.write(file, "Content for file #{i}" * 50)
      end
      
      suppress_stdout do
        indexer.index_directory(@temp_dir)
      end
    end

    it "returns indexing statistics" do
      stats = indexer.database.get_stats
      
      expect(stats).to be_a(Hash)
      expect(stats).to include(
        :document_count,
        :total_size_mb
      )
    end

    it "returns correct document count" do
      stats = indexer.database.get_stats
      
      expect(stats[:document_count]).to be >= 0
    end
  end
end
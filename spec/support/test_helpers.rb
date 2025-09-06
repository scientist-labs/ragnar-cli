# frozen_string_literal: true

module TestHelpers
  def temp_dir
    @temp_dir ||= Dir.mktmpdir("ragnar_spec")
  end
  
  def temp_file(name, content)
    path = File.join(temp_dir, name)
    File.write(path, content)
    path
  end
  
  def cleanup_temp_files
    if @temp_dir && Dir.exist?(@temp_dir)
      FileUtils.rm_rf(@temp_dir)
    end
    @temp_paths&.each do |path|
      FileUtils.rm_rf(path) if File.exist?(path)
    end
  end
  
  def track_temp_path(path)
    @temp_paths ||= []
    @temp_paths << path
    path
  end
  
  # Create a temporary database path
  def temp_db_path
    track_temp_path(File.join(Dir.tmpdir, "ragnar_test_#{SecureRandom.hex(8)}.lance"))
  end
  
  # Capture stdout for testing CLI output
  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end
  
  # Suppress stdout during tests
  def suppress_output
    original_stdout = $stdout
    original_stderr = $stderr
    $stdout = StringIO.new
    $stderr = StringIO.new
    yield
  ensure
    $stdout = original_stdout
    $stderr = original_stderr
  end
  
  # Create sample documents for testing
  def sample_documents(count = 3)
    (1..count).map do |i|
      {
        id: "doc_#{i}",
        chunk_text: "Sample text for document #{i}. This contains information about topic #{i}.",
        file_path: "file_#{i}.txt",
        chunk_index: 0,
        embedding: fake_embedding_for("doc_#{i}"),
        metadata: { source: "test" }
      }
    end
  end
  
  # Create sample text files
  def create_sample_files
    [
      temp_file("ruby.txt", "Ruby is a dynamic programming language known for simplicity and productivity."),
      temp_file("python.txt", "Python is a high-level language that emphasizes code readability."),
      temp_file("javascript.txt", "JavaScript is a scripting language for web browsers and Node.js.")
    ]
  end
end
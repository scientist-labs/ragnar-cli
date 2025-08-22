# frozen_string_literal: true

# Start SimpleCov before loading any application code
require "simplecov"
SimpleCov.start do
  # Add filters to exclude non-application code
  add_filter "/spec/"
  add_filter "/vendor/"
  add_filter "/.bundle/"
  
  # Group files for better organization in the coverage report
  add_group "Core", "lib/ragnar"
  add_group "CLI", "lib/ragnar/cli"
  add_group "Database", ["lib/ragnar/database", "lib/ragnar/indexer"]
  add_group "Processing", ["lib/ragnar/chunker", "lib/ragnar/embedder", "lib/ragnar/query_processor"]
  add_group "Topic Modeling", "lib/ragnar/topic_modeling"
  
  # Set minimum coverage percentage (optional)
  # Temporarily lowered - aiming to improve to 80%
  minimum_coverage 20
  
  # Use a nice HTML formatter
  formatter SimpleCov::Formatter::HTMLFormatter
end

require "bundler/setup"
require "ragnar"
require "tempfile"
require "fileutils"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Run specs in random order to surface order dependencies
  config.order = :random

  # Seed global randomization in this process using the `--seed` CLI option
  Kernel.srand config.seed

  # Helper method to create temporary directories for testing
  config.around(:each, :temp_dir) do |example|
    Dir.mktmpdir do |temp_dir|
      @temp_dir = temp_dir
      example.run
    end
  end

  # Helper method to capture stdout
  def capture_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end

  # Helper method to suppress stdout during tests
  def suppress_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
  ensure
    $stdout = original_stdout
  end
end
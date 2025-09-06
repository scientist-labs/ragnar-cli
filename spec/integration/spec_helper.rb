# frozen_string_literal: true

# Integration test helper - loads main spec_helper but disables mocks
require_relative "../spec_helper"

RSpec.configure do |config|
  # Integration tests use real components - no additional stubbing needed
  
  config.before(:suite) do
    puts "\n=== Running INTEGRATION tests with REAL components ==="
    puts "Note: These tests will be slower as they use actual models\n\n"
  end
  
  # Tag all integration specs
  config.define_derived_metadata(file_path: %r{/spec/integration/}) do |metadata|
    metadata[:integration] = true
  end
end
# frozen_string_literal: true

require "bundler/setup"
require "ragnar"
require "tmpdir"
require "securerandom"

# Load support files
Dir[File.join(__dir__, "support", "*.rb")].each { |f| require f }

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
  
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end
  
  config.filter_run :focus
  config.run_all_when_everything_filtered = true
  config.order = :random
  config.disable_monkey_patching!
  
  # Include helpers in all specs
  config.include MockHelpers
  config.include TestHelpers
  
  # Global before - stub slow operations by default
  config.before(:each) do
    stub_embeddings unless self.class.metadata[:real_embeddings]
    stub_llm unless self.class.metadata[:real_llm]
  end
  
  # Clean up temp files after each test
  config.after(:each) do
    cleanup_temp_files
  end
end
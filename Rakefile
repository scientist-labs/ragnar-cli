# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

# Default spec task - runs unit tests and CLI integration (fast, mocked)
RSpec::Core::RakeTask.new(:spec) do |t|
  t.pattern = "spec/{unit,integration/cli}/**/*_spec.rb"
  t.rspec_opts = "--format progress"
end

namespace :spec do
  desc "Run fast unit tests only"
  RSpec::Core::RakeTask.new(:unit) do |t|
    t.pattern = "spec/unit/**/*_spec.rb"
    t.rspec_opts = "--format progress"
  end
  
  desc "Run end-to-end integration tests (slow, requires real models)"
  RSpec::Core::RakeTask.new(:e2e) do |t|
    t.pattern = "spec/integration/*_spec.rb"
    t.rspec_opts = "--format documentation"
    ENV['RUN_INTEGRATION'] = 'true'
  end
  
  desc "Run tests with coverage report"
  task :coverage do
    ENV['COVERAGE'] = 'true'
    Rake::Task["spec:unit"].invoke
  end
end

require "rubocop/rake_task"
RuboCop::RakeTask.new

# Default task runs fast tests only
task default: %i[spec rubocop]

# Task for CI/CD - runs all tests
task ci: ["spec:all", :rubocop]
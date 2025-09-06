# frozen_string_literal: true

require_relative "lib/ragnar/version"

Gem::Specification.new do |spec|
  spec.name = "ragnar-cli"
  spec.version = Ragnar::VERSION
  spec.authors = ["Chris Petersen"]
  spec.email = ["chris@example.com"]

  spec.summary = "A Ruby + Rust powered RAG (Retrieval-Augmented Generation) system"
  spec.description = "Ragnar is a high-performance RAG system that leverages Rust libraries through Ruby bindings for embeddings, vector search, and topic modeling. It provides a complete CLI for indexing documents and querying with LLMs."
  spec.homepage = "https://github.com/cpetersen/ragnar"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.chdir(__dir__) do
    Dir.glob("{lib,exe}/**/*", File::FNM_DOTMATCH).reject do |f|
      File.directory?(f)
    end + ["README.md", "LICENSE.txt"]
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "thor", "~> 1.3"
  spec.add_dependency "red-candle", "~> 1.2"
  spec.add_dependency "lancelot", "~> 0.3", ">= 0.3.3"
  spec.add_dependency "topical", "~> 0.1.0", ">= 0.1.1"
  spec.add_dependency "baran", "~> 0.2"
  spec.add_dependency "parsekit", "~> 0.1", ">= 0.1.2"
  spec.add_dependency "tty-progressbar", "~> 0.18"

  # Development dependencies
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rubocop", "~> 1.21"
  spec.add_development_dependency "simplecov", "~> 0.22"
end

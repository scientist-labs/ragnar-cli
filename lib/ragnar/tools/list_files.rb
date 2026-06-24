# frozen_string_literal: true

module Ragnar
  module Tools
    class ListFiles < RubyLLM::Tool
      description "List files matching a glob pattern. Returns file paths sorted by modification time."

      param :pattern, desc: "Glob pattern (e.g., '**/*.rb', 'src/**/*.ts', 'lib/*.rb')"
      param :path, desc: "Base directory to search in (default: current directory)", required: false

      def execute(pattern:, path: nil)
        base = File.expand_path(path || ".")

        unless Dir.exist?(base)
          return "Error: Directory not found: #{base}"
        end

        full_pattern = File.join(base, pattern)
        matches = Dir.glob(full_pattern).sort_by { |f| File.mtime(f) rescue Time.at(0) }.reverse

        if matches.empty?
          return "No files found matching: #{pattern}"
        end

        # Limit output
        total = matches.length
        shown = matches.first(100)

        result = shown.map { |f| f.sub("#{base}/", "") }.join("\n")
        result += "\n... and #{total - 100} more" if total > 100
        result
      rescue => e
        "Error listing files: #{e.message}"
      end
    end
  end
end

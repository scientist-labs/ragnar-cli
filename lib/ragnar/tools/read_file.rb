# frozen_string_literal: true

module Ragnar
  module Tools
    class ReadFile < RubyLLM::Tool
      description "Read the contents of a file. Returns the file text with line numbers."

      param :path, desc: "The absolute or relative path to the file to read"
      param :offset, desc: "Line number to start reading from (1-based)", type: :integer, required: false
      param :limit, desc: "Maximum number of lines to read", type: :integer, required: false

      def execute(path:, offset: nil, limit: nil)
        expanded = File.expand_path(path)

        unless File.exist?(expanded)
          return "Error: File not found: #{path}"
        end

        unless File.file?(expanded)
          return "Error: Not a file: #{path}"
        end

        lines = File.readlines(expanded)

        # Apply offset and limit
        start_line = [(offset || 1) - 1, 0].max
        end_line = limit ? start_line + limit : lines.length
        selected = lines[start_line...end_line] || []

        # Format with line numbers
        selected.each_with_index.map do |line, idx|
          "#{start_line + idx + 1}\t#{line}"
        end.join
      rescue => e
        "Error reading file: #{e.message}"
      end
    end
  end
end

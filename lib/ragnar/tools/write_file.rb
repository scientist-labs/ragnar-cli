# frozen_string_literal: true

module Ragnar
  module Tools
    class WriteFile < RubyLLM::Tool
      description "Write content to a file. Creates the file if it doesn't exist, overwrites if it does. Creates parent directories as needed."

      param :path, desc: "The absolute or relative path to the file to write"
      param :content, desc: "The full content to write to the file"

      def execute(path:, content:)
        expanded = File.expand_path(path)

        # Create parent directories
        FileUtils.mkdir_p(File.dirname(expanded))

        File.write(expanded, content)
        "Successfully wrote #{content.length} bytes to #{path}"
      rescue => e
        "Error writing file: #{e.message}"
      end
    end
  end
end

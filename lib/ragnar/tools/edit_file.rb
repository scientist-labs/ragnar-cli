# frozen_string_literal: true

module Ragnar
  module Tools
    class EditFile < RubyLLM::Tool
      description "Edit a file by replacing a specific string with new content. The old_string must match exactly (including whitespace and indentation)."

      param :path, desc: "The absolute or relative path to the file to edit"
      param :old_string, desc: "The exact text to find and replace"
      param :new_string, desc: "The replacement text"

      def execute(path:, old_string:, new_string:)
        expanded = File.expand_path(path)

        unless File.exist?(expanded)
          return "Error: File not found: #{path}"
        end

        content = File.read(expanded)

        unless content.include?(old_string)
          return "Error: old_string not found in #{path}. Make sure it matches exactly, including whitespace."
        end

        occurrences = content.scan(old_string).length
        if occurrences > 1
          return "Error: old_string found #{occurrences} times in #{path}. Provide more context to make it unique."
        end

        new_content = content.sub(old_string, new_string)
        File.write(expanded, new_content)
        "Successfully edited #{path}"
      rescue => e
        "Error editing file: #{e.message}"
      end
    end
  end
end

# frozen_string_literal: true

module Ragnar
  module Tools
    # Lite tool set for local models (Qwen3-8B, etc.)
    #
    # Small local models get overwhelmed when too many tools with long
    # descriptions are registered. The full tool set (9 tools) causes
    # Qwen3-8B to output only <think> blocks without making any tool calls.
    # With 4 tools and short descriptions, it works reliably.
    #
    # Cloud models (Claude, GPT-4) handle the full tool set fine.

    class LiteWriteFile < RubyLLM::Tool
      description "Write a file"
      param :path, desc: "File path"
      param :content, desc: "File content"

      def execute(path:, content:)
        expanded = File.expand_path(path)
        FileUtils.mkdir_p(File.dirname(expanded))
        File.write(expanded, content)
        "Wrote #{content.length} bytes to #{path}"
      rescue => e
        "Error: #{e.message}"
      end
    end

    class LiteReadFile < RubyLLM::Tool
      description "Read a file"
      param :path, desc: "File path"

      def execute(path:)
        expanded = File.expand_path(path)
        return "Error: not found: #{path}" unless File.exist?(expanded)
        File.read(expanded)
      rescue => e
        "Error: #{e.message}"
      end
    end

    class LiteBashExec < RubyLLM::Tool
      description "Run a bash command"
      param :command, desc: "The command to run"

      def execute(command:)
        stdout, stderr, status = Open3.capture3("bash", "-c", command, stdin_data: "")
        parts = ["Exit: #{status.exitstatus}"]
        parts << stdout unless stdout.empty?
        parts << "stderr: #{stderr}" unless stderr.empty?
        parts.join("\n")
      rescue => e
        "Error: #{e.message}"
      end
    end

    class LiteTaskComplete < RubyLLM::Tool
      description "Signal that the task is done"
      param :summary, desc: "What was done"

      def execute(summary:)
        halt(summary)
      end
    end

    LITE = [
      LiteReadFile,
      LiteWriteFile,
      LiteBashExec,
      LiteTaskComplete
    ].freeze
  end
end

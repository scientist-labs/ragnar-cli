# frozen_string_literal: true

require "open3"
require "shellwords"

module Ragnar
  module Tools
    class BashExec < RubyLLM::Tool
      description "Execute a bash command and return stdout, stderr, and exit code. Use for running tests, installing dependencies, checking git status, etc."

      param :command, desc: "The bash command to execute"
      param :timeout, desc: "Timeout in seconds (default: 30)", type: :integer, required: false

      BLOCKED_PATTERNS = [
        /\brm\s+-rf\s+[\/~]/,       # rm -rf / or ~
        /\bmkfs\b/,                   # format filesystem
        /\bdd\b.*of=\/dev/,           # dd to device
        />\s*\/dev\/sd/,              # write to block device
        /\bshutdown\b/,
        /\breboot\b/,
      ].freeze

      def execute(command:, timeout: 30)
        # Basic safety check
        BLOCKED_PATTERNS.each do |pattern|
          if command.match?(pattern)
            return "Error: Command blocked for safety: #{command}"
          end
        end

        timeout = [timeout || 30, 300].min  # Cap at 5 minutes

        stdout, stderr, status = Open3.capture3("bash", "-c", command, stdin_data: "")

        # Truncate very long output
        stdout = truncate(stdout, 10_000)
        stderr = truncate(stderr, 5_000)

        parts = []
        parts << "Exit code: #{status.exitstatus}"
        parts << "stdout:\n#{stdout}" unless stdout.empty?
        parts << "stderr:\n#{stderr}" unless stderr.empty?
        parts.join("\n\n")
      rescue Timeout::Error
        "Error: Command timed out after #{timeout} seconds"
      rescue => e
        "Error executing command: #{e.message}"
      end

      private

      def truncate(text, max_length)
        return text if text.length <= max_length
        text[0...max_length] + "\n... (truncated, #{text.length} total bytes)"
      end
    end
  end
end

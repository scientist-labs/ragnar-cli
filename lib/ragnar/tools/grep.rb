# frozen_string_literal: true

module Ragnar
  module Tools
    class Grep < RubyLLM::Tool
      description "Search file contents for a pattern using ripgrep (rg) or grep. Returns matching lines with file paths and line numbers."

      param :pattern, desc: "The regex pattern to search for"
      param :path, desc: "File or directory to search in (default: current directory)", required: false
      param :glob, desc: "File glob filter (e.g., '*.rb', '*.{ts,tsx}')", required: false

      def execute(pattern:, path: nil, glob: nil)
        base = File.expand_path(path || ".")

        # Prefer ripgrep, fall back to grep
        if system("which rg > /dev/null 2>&1")
          cmd = ["rg", "--no-heading", "--line-number", "--max-count=100"]
          cmd += ["--glob", glob] if glob
          cmd += [pattern, base]
        else
          cmd = ["grep", "-rn", "--max-count=100"]
          cmd += ["--include=#{glob}"] if glob
          cmd += [pattern, base]
        end

        stdout, stderr, status = Open3.capture3(*cmd)

        if stdout.empty? && status.exitstatus == 1
          return "No matches found for: #{pattern}"
        end

        if status.exitstatus > 1
          return "Error: #{stderr}"
        end

        # Truncate long output
        lines = stdout.lines
        if lines.length > 100
          lines.first(100).join + "\n... (#{lines.length} total matches)"
        else
          stdout
        end
      rescue => e
        "Error searching: #{e.message}"
      end
    end
  end
end

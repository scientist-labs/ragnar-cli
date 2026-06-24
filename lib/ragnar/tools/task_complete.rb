# frozen_string_literal: true

module Ragnar
  module Tools
    # How does the agent signal "I'm done"?
    #
    # Early versions used string matching ("I've completed", "all done") to detect
    # when the LLM was finished. This was fragile — the orchestrator would keep
    # looping because it didn't match the exact phrase.
    #
    # The solution: make completion a tool call, not prose. When the agent is done,
    # it calls this tool. RubyLLM's `halt` mechanism immediately stops the tool
    # execution loop and returns the summary to the orchestrator. No ambiguity,
    # no extra iterations, no string parsing.
    #
    # This is the same pattern used by production coding agents — explicit signaling
    # via the tool protocol rather than natural language detection.
    class TaskComplete < RubyLLM::Tool
      description "Call this when you have finished the task. Provide a brief summary of what was accomplished. This signals the orchestrator to stop."

      param :summary, desc: "Brief summary of what was accomplished"

      def execute(summary:)
        halt(summary)
      end
    end
  end
end

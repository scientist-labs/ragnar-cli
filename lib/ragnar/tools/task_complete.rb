# frozen_string_literal: true

module Ragnar
  module Tools
    class TaskComplete < RubyLLM::Tool
      description "Call this when you have finished the task. Provide a brief summary of what was accomplished. This signals the orchestrator to stop."

      param :summary, desc: "Brief summary of what was accomplished"

      def execute(summary:)
        halt(summary)
      end
    end
  end
end

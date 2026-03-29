# frozen_string_literal: true

module Ragnar
  module Tools
    class AskUser < RubyLLM::Tool
      description "Ask the user a question when you need clarification, confirmation, or a decision before proceeding. The user's response will be provided in the next turn."

      param :question, desc: "The question to ask the user"

      def execute(question:)
        halt(question)
      end
    end
  end
end

# frozen_string_literal: true

require_relative "tools/read_file"
require_relative "tools/write_file"
require_relative "tools/edit_file"
require_relative "tools/bash_exec"
require_relative "tools/list_files"
require_relative "tools/grep"
require_relative "tools/search_docs"
require_relative "tools/task_complete"
require_relative "tools/ask_user"

module Ragnar
  module Tools
    # All tools the agent can use. Each is a RubyLLM::Tool subclass.
    # The Agent registers these with the LLM chat — the LLM sees their
    # descriptions and JSON schemas, and can call any of them.
    #
    # To add a new tool: create a class in tools/, add it here.
    # The LLM will discover it automatically on the next conversation.
    ALL = [
      Tools::ReadFile,
      Tools::WriteFile,
      Tools::EditFile,
      Tools::BashExec,
      Tools::ListFiles,
      Tools::Grep,
      Tools::SearchDocs,
      Tools::TaskComplete,
      Tools::AskUser
    ].freeze
  end
end

# frozen_string_literal: true

require_relative "tools/read_file"
require_relative "tools/write_file"
require_relative "tools/edit_file"
require_relative "tools/bash_exec"
require_relative "tools/list_files"
require_relative "tools/grep"
require_relative "tools/task_complete"
require_relative "tools/ask_user"

module Ragnar
  module Tools
    ALL = [
      Tools::ReadFile,
      Tools::WriteFile,
      Tools::EditFile,
      Tools::BashExec,
      Tools::ListFiles,
      Tools::Grep,
      Tools::TaskComplete,
      Tools::AskUser
    ].freeze
  end
end

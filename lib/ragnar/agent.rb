# frozen_string_literal: true

module Ragnar
  # Agent wraps a persistent RubyLLM chat with tools and conversation state.
  # This is the Level 1 component — it handles a single LLM turn where the
  # model can make multiple tool calls. The Orchestrator (Level 2) manages
  # multiple Agent turns to complete a task.
  class Agent
    attr_reader :chat, :files_modified, :tool_calls_log

    SYSTEM_PROMPT = <<~PROMPT
      You are a helpful coding assistant. You have access to tools for reading files,
      writing files, editing files, executing bash commands, listing files, and searching
      file contents.

      When working on a task:
      1. Start by understanding the codebase — read relevant files, list directories
      2. Make changes incrementally — edit or write files as needed
      3. Verify your changes — run tests or check the output
      4. When finished, call the task_complete tool with a summary

      IMPORTANT:
      - When you have completed the task, you MUST call the task_complete tool. Do not
        just say you're done in text — use the tool.
      - If you need clarification from the user, call the ask_user tool.
      - Be concise and direct. Prefer editing existing files over creating new ones.
    PROMPT

    def initialize(profile: nil)
      config = Config.instance
      config.set_active_profile(profile) if profile

      @chat = config.create_chat
      @chat.with_instructions(SYSTEM_PROMPT)
      register_tools

      @files_modified = []
      @tool_calls_log = []
      @on_tool_call = nil
      @on_tool_result = nil
    end

    # Execute a single LLM turn. The model may make multiple tool calls
    # within this turn (Level 1 loop handled by RubyLLM).
    def step(message = nil)
      prompt = message || "Continue with the task."
      response = @chat.ask(prompt)
      response
    end

    # Convenience: set a task and get the first response
    def ask(question)
      step(question)
    end

    # Add context for the next turn (used by Orchestrator)
    def add_context(info)
      @pending_context = info
    end

    # Take the next step with any pending context
    def next_step
      message = @pending_context || "Continue with the task."
      @pending_context = nil
      step(message)
    end

    # Register callbacks for tool call visibility
    def on_tool_call(&block)
      @on_tool_call = block
      @chat.on_tool_call do |tool_call|
        @tool_calls_log << { name: tool_call.name, args: tool_call.arguments, time: Time.now }
        @on_tool_call&.call(tool_call)
      end
    end

    def on_tool_result(&block)
      @on_tool_result = block
      @chat.on_tool_result do |result|
        # Track file modifications
        track_modification(result)
        @on_tool_result&.call(result)
      end
    end

    # Reset conversation but keep tools
    def reset
      @chat.reset_messages!
      @chat.with_instructions(SYSTEM_PROMPT)
      @files_modified.clear
      @tool_calls_log.clear
    end

    private

    def register_tools
      Ragnar::Tools::ALL.each do |tool_class|
        @chat.with_tool(tool_class.new)
      end
    end

    def track_modification(result)
      # Check if the last tool call was a file-modifying operation
      last_call = @tool_calls_log.last
      return unless last_call

      case last_call[:name]
      when "ragnar-tools-write_file", "ragnar-tools-edit_file"
        path = last_call[:args]&.dig("path") || last_call[:args]&.dig(:path)
        @files_modified << path if path && !@files_modified.include?(path)
      end
    end
  end
end

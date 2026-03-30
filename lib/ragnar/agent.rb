# frozen_string_literal: true

module Ragnar
  # The Agent wraps a persistent RubyLLM chat with tools and conversation state.
  #
  # This is the Level 1 component. When you call agent.step("fix the bug"),
  # RubyLLM sends the message to the LLM along with descriptions of all
  # registered tools. The LLM may respond with tool calls (read_file, edit_file,
  # bash_exec) which RubyLLM executes automatically and feeds back — all within
  # a single call to chat.ask(). This inner loop is free; RubyLLM handles it.
  #
  # The Agent maintains conversation history across steps, so the Orchestrator
  # (Level 2) can call step() multiple times and the LLM remembers what it did.
  # Each tool call is logged for the Orchestrator to inspect (e.g., to detect
  # file modifications or completion signals).
  class Agent
    attr_reader :chat, :files_modified, :tool_calls_log

    SYSTEM_PROMPT = <<~PROMPT
      You are a helpful assistant with two types of capabilities:

      KNOWLEDGE BASE (search_docs tool):
        Search indexed documents, policies, and documentation. Use this when the user
        asks questions about information that would be in documents — "what is our
        password policy?", "how does authentication work?", etc.

      CODING TOOLS (read_file, write_file, edit_file, bash_exec, list_files, grep):
        Read and modify source code files, and run commands. Use these when the user
        asks you to examine, create, or modify code — "fix the bug in parser.rb",
        "create a fizzbuzz script", etc.

      Guidelines:
      - Questions about information/knowledge → use search_docs first
      - Tasks involving file changes → use coding tools
      - Hybrid tasks ("summarize our security docs into a file") → search_docs to
        gather information, then coding tools to create the output
      - When finished, ALWAYS call task_complete with a summary
      - If you need clarification, call ask_user
      - Be concise and direct
      /no_think
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
      tools = select_tool_set
      tools.each do |tool_class|
        @chat.with_tool(tool_class.new)
      end
    end

    # Local models (red_candle) get overwhelmed by many tools with long
    # descriptions — Qwen3-8B outputs only <think> blocks with 9 tools.
    # Cloud models (Anthropic, OpenAI) handle the full set fine.
    def select_tool_set
      provider = Config.instance.llm_provider
      if provider == 'red_candle'
        Ragnar::Tools::LITE
      else
        Ragnar::Tools::ALL
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

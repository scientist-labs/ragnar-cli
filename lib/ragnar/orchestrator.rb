# frozen_string_literal: true

module Ragnar
  # Orchestrator is the Level 2 loop — the "brain outside the brain."
  #
  # While the Agent handles a single LLM turn (with tool calls), the Orchestrator
  # manages multiple turns to complete a task:
  #
  #   1. Give the Agent a task
  #   2. After each turn, check: did files change? Run validation.
  #   3. If validation fails, feed the failure back and let the Agent try again
  #   4. If the Agent says it's done, verify and return
  #   5. If too many iterations, ask the user
  #
  # The key insight: the Orchestrator runs tests/validation BETWEEN LLM turns.
  # The LLM doesn't ask to run tests — the Orchestrator does it automatically.
  class Orchestrator
    attr_reader :agent, :iteration, :max_iterations, :working_dir

    def initialize(agent:, working_dir: Dir.pwd, max_iterations: 20)
      @agent = agent
      @working_dir = File.expand_path(working_dir)
      @max_iterations = max_iterations
      @iteration = 0
      @on_status = nil
      @on_response = nil
    end

    # Run a task to completion. Yields for user input when needed.
    #
    # Usage:
    #   orchestrator.run("Add a login page") do |event|
    #     case event[:type]
    #     when :response    then puts event[:content]
    #     when :tool_call   then puts "Using: #{event[:name]}"
    #     when :validation  then puts "Running: #{event[:command]}"
    #     when :status      then puts event[:message]
    #     when :ask_user    then gets.chomp  # return user's answer
    #     end
    #   end
    def run(task, &callback)
      @iteration = 0
      emit(callback, type: :status, message: "Starting task...")

      # First turn: give the agent the task
      response = @agent.ask(task)

      loop do
        @iteration += 1
        signal = detect_signal(response)

        case signal
        when :task_complete
          emit(callback, type: :response, content: response.content)
          emit(callback, type: :status, message: "Task complete (iteration #{@iteration})")

          # If files were modified, run validation before accepting
          if @agent.files_modified.any?
            validation = run_validation(callback)
            if validation && !validation[:passed]
              emit(callback, type: :status, message: "Validation failed, asking agent to fix...")
              @agent.add_context(
                "You called task_complete but validation failed:\n\n#{validation[:output]}\n\nPlease fix the issues and call task_complete again when done."
              )
              response = @agent.next_step
              next
            end
          end
          break

        when :ask_user
          user_response = emit(callback, type: :ask_user, message: response.content)
          @agent.add_context("User response: #{user_response}")
          response = @agent.next_step
          next

        else
          # Normal response — the agent is still working
          emit(callback, type: :response, content: response.content) if response.content && !response.content.empty?

          # Check iteration limit
          if @iteration > @max_iterations
            answer = emit(callback,
              type: :ask_user,
              message: "Reached #{@max_iterations} iterations. Continue? (y/n)")
            break unless answer&.strip&.downcase == "y"
            @max_iterations += 10
          end

          # Agent didn't signal — let it continue
          response = @agent.next_step
        end
      end

      response
    end

    private

    def emit(callback, event)
      return unless callback
      callback.call(event)
    end

    # Detect tool-based signals from the agent.
    # When the agent calls TaskComplete or AskUser, RubyLLM's halt mechanism
    # stops the tool loop and returns the tool's message as the response content.
    # We detect which tool was called by checking the agent's tool call log.
    def detect_signal(response)
      last_call = @agent.tool_calls_log.last
      return :continue unless last_call

      case last_call[:name]
      when /task_complete/
        :task_complete
      when /ask_user/
        :ask_user
      else
        :continue
      end
    end

    def run_validation(callback)
      # Detect project type and run appropriate validation
      validator = detect_validator
      return nil unless validator

      emit(callback, type: :validation, command: validator[:command])

      Dir.chdir(@working_dir) do
        stdout, stderr, status = Open3.capture3(validator[:command])
        output = [stdout, stderr].reject(&:empty?).join("\n")

        {
          passed: status.success?,
          output: output.length > 5000 ? output[0..5000] + "\n...(truncated)" : output,
          command: validator[:command],
          exit_code: status.exitstatus
        }
      end
    rescue => e
      emit(callback, type: :status, message: "Validation error: #{e.message}")
      nil
    end

    def detect_validator
      if File.exist?(File.join(@working_dir, "Gemfile"))
        if File.exist?(File.join(@working_dir, "spec"))
          { command: "bundle exec rspec --format progress", type: :ruby }
        elsif File.exist?(File.join(@working_dir, "test"))
          { command: "bundle exec rake test", type: :ruby }
        end
      elsif File.exist?(File.join(@working_dir, "Cargo.toml"))
        { command: "cargo test", type: :rust }
      elsif File.exist?(File.join(@working_dir, "package.json"))
        { command: "npm test", type: :node }
      elsif File.exist?(File.join(@working_dir, "pyproject.toml")) ||
            File.exist?(File.join(@working_dir, "setup.py"))
        { command: "python -m pytest", type: :python }
      end
    end
  end
end

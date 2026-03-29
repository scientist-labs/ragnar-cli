# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ragnar::Orchestrator do
  let(:mock_chat) { mock_ruby_llm_chat }
  let(:agent) { Ragnar::Agent.new }
  let(:orchestrator) { described_class.new(agent: agent, working_dir: temp_dir) }

  before do
    allow(RubyLLM).to receive(:chat).and_return(mock_chat)
    allow(mock_chat).to receive(:with_instructions).and_return(mock_chat)
    allow(mock_chat).to receive(:with_tool).and_return(mock_chat)
    allow(mock_chat).to receive(:on_tool_call).and_return(mock_chat)
    allow(mock_chat).to receive(:on_tool_result).and_return(mock_chat)
  end

  describe "#initialize" do
    it "sets up with agent and working directory" do
      expect(orchestrator.agent).to eq(agent)
      expect(orchestrator.max_iterations).to eq(20)
      expect(orchestrator.iteration).to eq(0)
    end

    it "accepts custom max_iterations" do
      orch = described_class.new(agent: agent, max_iterations: 5)
      expect(orch.max_iterations).to eq(5)
    end
  end

  describe "#run" do
    let(:response) do
      resp = double("RubyLLM::Message")
      allow(resp).to receive(:content).and_return("Done with the task.")
      resp
    end

    it "completes when agent calls task_complete tool" do
      allow(mock_chat).to receive(:ask).and_return(response)

      # Simulate the agent calling task_complete
      agent.tool_calls_log << { name: "ragnar--tools--task_complete", args: { summary: "Done" }, time: Time.now }

      events = []
      orchestrator.run("Fix the bug") do |event|
        events << event
      end

      statuses = events.select { |e| e[:type] == :status }.map { |e| e[:message] }
      expect(statuses).to include(/Task complete/)
    end

    it "handles ask_user signal" do
      allow(mock_chat).to receive(:ask).and_return(response)

      call_count = 0
      allow(mock_chat).to receive(:ask) do
        call_count += 1
        if call_count == 1
          # First turn: agent asks user a question
          agent.tool_calls_log << { name: "ragnar--tools--ask_user", args: { question: "Which framework?" }, time: Time.now }
          resp = double("RubyLLM::Message")
          allow(resp).to receive(:content).and_return("Which framework?")
          resp
        else
          # Second turn: agent completes
          agent.tool_calls_log << { name: "ragnar--tools--task_complete", args: { summary: "Done" }, time: Time.now }
          resp = double("RubyLLM::Message")
          allow(resp).to receive(:content).and_return("All done.")
          resp
        end
      end

      events = []
      orchestrator.run("Build something") do |event|
        events << event
        "rspec" if event[:type] == :ask_user  # Answer the question
      end

      types = events.map { |e| e[:type] }
      expect(types).to include(:ask_user)
    end

    it "continues when no signal is given" do
      call_count = 0
      allow(mock_chat).to receive(:ask) do
        call_count += 1
        if call_count >= 3
          agent.tool_calls_log << { name: "ragnar--tools--task_complete", args: {}, time: Time.now }
        end
        resp = double("RubyLLM::Message")
        allow(resp).to receive(:content).and_return("Working...")
        resp
      end

      orchestrator.run("Multi-step task") { |e| }
      expect(orchestrator.iteration).to be >= 2
    end

    it "respects max_iterations" do
      allow(mock_chat).to receive(:ask) do
        resp = double("RubyLLM::Message")
        allow(resp).to receive(:content).and_return("Still working...")
        resp
      end

      orch = described_class.new(agent: agent, working_dir: temp_dir, max_iterations: 2)

      orch.run("Infinite task") do |event|
        "n" if event[:type] == :ask_user
      end

      expect(orch.iteration).to be <= 3
    end
  end

  describe "#detect_signal" do
    let(:response) { double("RubyLLM::Message", content: "text") }

    it "returns :task_complete when last tool call was task_complete" do
      agent.tool_calls_log << { name: "ragnar--tools--task_complete", args: {}, time: Time.now }
      expect(orchestrator.send(:detect_signal, response)).to eq(:task_complete)
    end

    it "returns :ask_user when last tool call was ask_user" do
      agent.tool_calls_log << { name: "ragnar--tools--ask_user", args: {}, time: Time.now }
      expect(orchestrator.send(:detect_signal, response)).to eq(:ask_user)
    end

    it "returns :continue when last tool call was something else" do
      agent.tool_calls_log << { name: "ragnar--tools--read_file", args: {}, time: Time.now }
      expect(orchestrator.send(:detect_signal, response)).to eq(:continue)
    end

    it "returns :continue when no tool calls" do
      expect(orchestrator.send(:detect_signal, response)).to eq(:continue)
    end
  end

  describe "#detect_validator" do
    it "detects Ruby projects with rspec" do
      FileUtils.touch(File.join(temp_dir, "Gemfile"))
      FileUtils.mkdir_p(File.join(temp_dir, "spec"))

      validator = orchestrator.send(:detect_validator)
      expect(validator[:command]).to include("rspec")
    end

    it "detects Rust projects" do
      FileUtils.touch(File.join(temp_dir, "Cargo.toml"))

      validator = orchestrator.send(:detect_validator)
      expect(validator[:command]).to include("cargo test")
    end

    it "returns nil for unknown project types" do
      validator = orchestrator.send(:detect_validator)
      expect(validator).to be_nil
    end
  end
end

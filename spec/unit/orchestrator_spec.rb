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
    let(:complete_response) do
      resp = double("RubyLLM::Message")
      allow(resp).to receive(:content).and_return("I've completed the task.")
      resp
    end

    let(:incomplete_response) do
      resp = double("RubyLLM::Message")
      allow(resp).to receive(:content).and_return("I'm working on it...")
      resp
    end

    it "completes when agent says task is done" do
      allow(mock_chat).to receive(:ask).and_return(complete_response)

      events = []
      orchestrator.run("Fix the bug") do |event|
        events << event
      end

      expect(events.map { |e| e[:type] }).to include(:status, :response)
    end

    it "tracks iterations" do
      call_count = 0
      allow(mock_chat).to receive(:ask) do
        call_count += 1
        if call_count >= 2
          complete_response
        else
          incomplete_response
        end
      end

      orchestrator.run("Do something") { |e| }
      expect(orchestrator.iteration).to be >= 1
    end

    it "respects max_iterations" do
      allow(mock_chat).to receive(:ask).and_return(incomplete_response)

      orch = described_class.new(agent: agent, working_dir: temp_dir, max_iterations: 2)

      events = []
      orch.run("Infinite task") do |event|
        events << event
        "n" if event[:type] == :ask_user  # Don't continue
      end

      expect(orch.iteration).to be <= 3
    end
  end

  describe "#detect_validator" do
    it "detects Ruby projects with rspec" do
      FileUtils.touch(File.join(temp_dir, "Gemfile"))
      FileUtils.mkdir_p(File.join(temp_dir, "spec"))

      validator = orchestrator.send(:detect_validator)
      expect(validator[:command]).to include("rspec")
      expect(validator[:type]).to eq(:ruby)
    end

    it "detects Rust projects" do
      FileUtils.touch(File.join(temp_dir, "Cargo.toml"))

      validator = orchestrator.send(:detect_validator)
      expect(validator[:command]).to include("cargo test")
      expect(validator[:type]).to eq(:rust)
    end

    it "detects Node projects" do
      FileUtils.touch(File.join(temp_dir, "package.json"))

      validator = orchestrator.send(:detect_validator)
      expect(validator[:command]).to include("npm test")
      expect(validator[:type]).to eq(:node)
    end

    it "returns nil for unknown project types" do
      validator = orchestrator.send(:detect_validator)
      expect(validator).to be_nil
    end
  end
end

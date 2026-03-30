# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ragnar::Agent do
  let(:mock_chat) { mock_ruby_llm_chat }

  before do
    allow(RubyLLM).to receive(:chat).and_return(mock_chat)
    allow(mock_chat).to receive(:with_instructions).and_return(mock_chat)
    allow(mock_chat).to receive(:with_tool).and_return(mock_chat)
    allow(mock_chat).to receive(:on_tool_call).and_return(mock_chat)
    allow(mock_chat).to receive(:on_tool_result).and_return(mock_chat)
    allow(mock_chat).to receive(:reset_messages!)
  end

  describe "#initialize" do
    it "creates a chat with tools registered" do
      agent = described_class.new
      expect(mock_chat).to have_received(:with_instructions)
      # Tool count depends on provider — LITE (4) for red_candle, ALL (9) for cloud
      expect(mock_chat).to have_received(:with_tool).at_least(4).times
    end

    it "accepts a profile option" do
      allow(Ragnar::Config.instance).to receive(:set_active_profile)
      agent = described_class.new(profile: "opus")
      expect(Ragnar::Config.instance).to have_received(:set_active_profile).with("opus")
    end
  end

  describe "#ask" do
    it "sends a message and returns a response" do
      agent = described_class.new
      response = agent.ask("What files are in this directory?")
      expect(response).not_to be_nil
      expect(response.content).to be_a(String)
    end
  end

  describe "#step" do
    it "sends a message for a single turn" do
      agent = described_class.new
      response = agent.step("Do something")
      expect(mock_chat).to have_received(:ask).with("Do something")
    end

    it "uses default message when none provided" do
      agent = described_class.new
      agent.step
      expect(mock_chat).to have_received(:ask).with("Continue with the task.")
    end
  end

  describe "#add_context and #next_step" do
    it "uses pending context in next step" do
      agent = described_class.new
      agent.add_context("Tests failed: 3 failures")
      agent.next_step
      expect(mock_chat).to have_received(:ask).with("Tests failed: 3 failures")
    end

    it "clears pending context after use" do
      agent = described_class.new
      agent.add_context("context info")
      agent.next_step
      agent.next_step
      expect(mock_chat).to have_received(:ask).with("Continue with the task.").at_least(:once)
    end
  end

  describe "#reset" do
    it "clears conversation and state" do
      agent = described_class.new
      agent.ask("first message")
      agent.reset
      expect(mock_chat).to have_received(:reset_messages!)
      expect(agent.files_modified).to be_empty
      expect(agent.tool_calls_log).to be_empty
    end
  end
end

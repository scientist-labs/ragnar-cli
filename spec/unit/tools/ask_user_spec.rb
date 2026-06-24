# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ragnar::Tools::AskUser do
  let(:tool) { described_class.new }

  describe "#execute" do
    it "returns a halt with the question" do
      result = tool.execute(question: "Should I use rspec or minitest?")
      expect(result).to be_a(RubyLLM::Tool::Halt)
      expect(result.content).to eq("Should I use rspec or minitest?")
    end
  end

  describe "tool metadata" do
    it "has a description mentioning clarification" do
      expect(tool.description).to include("clarification")
    end

    it "has a name" do
      expect(tool.name).to include("ask_user")
    end
  end
end

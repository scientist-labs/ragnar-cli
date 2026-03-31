# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ragnar::Tools::TaskComplete do
  let(:tool) { described_class.new }

  describe "#execute" do
    it "returns a halt with the summary" do
      result = tool.execute(summary: "Created fizzbuzz.rb and ran it successfully")
      expect(result).to be_a(RubyLLM::Tool::Halt)
      expect(result.content).to eq("Created fizzbuzz.rb and ran it successfully")
    end
  end

  describe "tool metadata" do
    it "has a description mentioning completion" do
      expect(tool.description).to include("finished")
    end

    it "has a name" do
      expect(tool.name).to include("task_complete")
    end
  end
end

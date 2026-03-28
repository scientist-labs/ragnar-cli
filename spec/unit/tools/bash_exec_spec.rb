# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ragnar::Tools::BashExec do
  let(:tool) { described_class.new }

  describe "#execute" do
    it "executes a command and returns output" do
      result = tool.execute(command: "echo hello")
      expect(result).to include("Exit code: 0")
      expect(result).to include("hello")
    end

    it "captures stderr" do
      result = tool.execute(command: "echo error >&2")
      expect(result).to include("error")
    end

    it "returns exit code for failures" do
      result = tool.execute(command: "exit 1")
      expect(result).to include("Exit code: 1")
    end

    it "blocks dangerous commands" do
      result = tool.execute(command: "rm -rf /")
      expect(result).to include("blocked for safety")
    end

    it "blocks shutdown" do
      result = tool.execute(command: "shutdown now")
      expect(result).to include("blocked for safety")
    end

    it "allows safe commands" do
      result = tool.execute(command: "ls /tmp")
      expect(result).to include("Exit code: 0")
    end
  end
end

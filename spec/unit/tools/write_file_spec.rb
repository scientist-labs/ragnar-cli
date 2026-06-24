# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ragnar::Tools::WriteFile do
  let(:tool) { described_class.new }

  describe "#execute" do
    it "writes content to a file" do
      path = File.join(temp_dir, "output.txt")
      result = tool.execute(path: path, content: "hello world")
      expect(result).to include("Successfully wrote")
      expect(File.read(path)).to eq("hello world")
    end

    it "creates parent directories" do
      path = File.join(temp_dir, "nested", "dir", "file.txt")
      tool.execute(path: path, content: "test")
      expect(File.exist?(path)).to be true
    end

    it "overwrites existing files" do
      path = temp_file("existing.txt", "old content")
      tool.execute(path: path, content: "new content")
      expect(File.read(path)).to eq("new content")
    end
  end
end

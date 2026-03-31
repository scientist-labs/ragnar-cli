# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ragnar::Tools::ReadFile do
  let(:tool) { described_class.new }

  describe "#execute" do
    it "reads a file with line numbers" do
      path = temp_file("test.txt", "line 1\nline 2\nline 3\n")
      result = tool.execute(path: path)
      expect(result).to include("1\tline 1")
      expect(result).to include("2\tline 2")
      expect(result).to include("3\tline 3")
    end

    it "supports offset and limit" do
      path = temp_file("test.txt", "a\nb\nc\nd\ne\n")
      result = tool.execute(path: path, offset: 2, limit: 2)
      expect(result).to include("2\tb")
      expect(result).to include("3\tc")
      expect(result).not_to include("1\ta")
      expect(result).not_to include("4\td")
    end

    it "returns error for missing file" do
      result = tool.execute(path: "/nonexistent/file.txt")
      expect(result).to include("Error: File not found")
    end

    it "returns error for directory" do
      result = tool.execute(path: temp_dir)
      expect(result).to include("Error: Not a file")
    end
  end

  describe "tool metadata" do
    it "has a description" do
      expect(tool.description).to include("Read")
    end

    it "has a name" do
      expect(tool.name).to include("read_file")
    end
  end
end

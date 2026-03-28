# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ragnar::Tools::ListFiles do
  let(:tool) { described_class.new }

  describe "#execute" do
    it "lists files matching a pattern" do
      temp_file("a.rb", "")
      temp_file("b.rb", "")
      temp_file("c.txt", "")

      result = tool.execute(pattern: "*.rb", path: temp_dir)
      expect(result).to include("a.rb")
      expect(result).to include("b.rb")
      expect(result).not_to include("c.txt")
    end

    it "returns message when no files match" do
      result = tool.execute(pattern: "*.xyz", path: temp_dir)
      expect(result).to include("No files found")
    end

    it "returns error for nonexistent directory" do
      result = tool.execute(pattern: "*", path: "/nonexistent/dir")
      expect(result).to include("Error: Directory not found")
    end
  end
end

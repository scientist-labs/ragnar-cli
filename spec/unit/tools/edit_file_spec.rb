# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ragnar::Tools::EditFile do
  let(:tool) { described_class.new }

  describe "#execute" do
    it "replaces text in a file" do
      path = temp_file("code.rb", "def hello\n  puts 'hi'\nend\n")
      result = tool.execute(path: path, old_string: "puts 'hi'", new_string: "puts 'hello world'")
      expect(result).to include("Successfully edited")
      expect(File.read(path)).to include("puts 'hello world'")
    end

    it "returns error when old_string not found" do
      path = temp_file("code.rb", "def hello\nend\n")
      result = tool.execute(path: path, old_string: "nonexistent", new_string: "replacement")
      expect(result).to include("Error: old_string not found")
    end

    it "returns error when old_string is ambiguous" do
      path = temp_file("code.rb", "puts 'a'\nputs 'a'\n")
      result = tool.execute(path: path, old_string: "puts 'a'", new_string: "puts 'b'")
      expect(result).to include("found 2 times")
    end

    it "returns error for missing file" do
      result = tool.execute(path: "/nonexistent.rb", old_string: "a", new_string: "b")
      expect(result).to include("Error: File not found")
    end
  end
end

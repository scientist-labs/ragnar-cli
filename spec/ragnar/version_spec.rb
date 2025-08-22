# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Ragnar::VERSION" do
  it "is defined" do
    expect(Ragnar::VERSION).to be_a(String)
  end

  it "follows semantic versioning format" do
    pending "TODO: This is not correct while in pre-release"
    expect(Ragnar::VERSION).to match(/^\d+\.\d+\.\d+(\.\w+)?$/)
  end

  it "has major, minor, and patch versions" do
    parts = Ragnar::VERSION.split(".")
    expect(parts.size).to be >= 3

    major, minor, patch = parts[0..2]
    expect(major.to_i).to be >= 0
    expect(minor.to_i).to be >= 0
    expect(patch.to_i).to be >= 0
  end

  it "is frozen" do
    expect(Ragnar::VERSION).to be_frozen
  end
end
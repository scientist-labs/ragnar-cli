#!/usr/bin/env ruby
# Test ragnar without bundler

$LOAD_PATH.unshift(File.expand_path("lib", __dir__))
require "ragnar"

Ragnar::CLI.start(["--help"])
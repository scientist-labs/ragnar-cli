#!/usr/bin/env ruby

require 'bundler/setup'
$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'ragnar'
require 'benchmark'

# Initialize the query processor
processor = Ragnar::QueryProcessor.new

queries = [
  "What is Ruby?",
  "What programming paradigm does Ruby follow?",
  "Who created Ruby?",
  "What are the main features of Ruby?",
  "How does Ruby compare to other languages?"
]

puts "Processing #{queries.length} queries with LLM caching..."
puts "=" * 60

total_time = Benchmark.measure do
  queries.each_with_index do |query, idx|
    puts "\nQuery #{idx + 1}: #{query}"
    
    query_time = Benchmark.measure do
      result = processor.query(query)
      puts "Answer: #{result[:answer][0..150]}..."
      puts "Confidence: #{result[:confidence]}%"
    end
    
    puts "Query time: #{query_time.real.round(2)} seconds"
  end
end

puts "\n" + "=" * 60
puts "Total time for #{queries.length} queries: #{total_time.real.round(2)} seconds"
puts "Average time per query: #{(total_time.real / queries.length).round(2)} seconds"
puts "\nNote: The first query loads the LLM, subsequent queries use the cached instance."
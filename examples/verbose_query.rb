#!/usr/bin/env ruby

# Example demonstrating verbose query mode
# This shows all the intermediate steps in the RAG pipeline

require 'bundler/setup'
$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'ruby_rag'

puts <<~HEADER
================================================================================
                        RAG Query Pipeline - Verbose Mode
================================================================================

This example demonstrates the complete RAG pipeline with detailed output
showing each intermediate step from query analysis to final response.

HEADER

# Initialize the query processor
processor = RubyRag::QueryProcessor.new

# Example queries to demonstrate different aspects
queries = {
  "Simple factual" => "What is Ruby?",
  "Comparative" => "How does Ruby compare to Python?",
  "Technical detail" => "What design principles does Ruby follow?"
}

queries.each do |query_type, query|
  puts "\n" + "="*80
  puts "Query Type: #{query_type}"
  puts "="*80
  
  # Process with verbose output
  result = processor.query(query, top_k: 3, verbose: true)
  
  puts "\n" + "="*80
  puts "Summary for: #{query}"
  puts "-"*80
  puts "Confidence: #{result[:confidence]}%"
  puts "Sources: #{result[:sources].length} documents"
  puts "Answer length: #{result[:answer].length} characters"
  puts "="*80
  
  # Wait for user to continue
  puts "\nPress Enter to continue to next query..."
  gets
end

puts <<~FOOTER

================================================================================
                                    Complete!
================================================================================

The verbose mode showed:
1. Query rewriting and analysis
2. Sub-query generation
3. Embedding generation for each sub-query
4. Vector database search results
5. Reciprocal Rank Fusion combining results
6. Document reranking with relevance scores
7. Context preparation and repacking
8. LLM response generation
9. Final confidence scoring

This transparency helps debug issues and understand how the system works.
FOOTER
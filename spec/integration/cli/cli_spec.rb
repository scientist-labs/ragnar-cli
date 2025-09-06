# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ragnar::CLI, type: :integration do
  let(:temp_dir) { Dir.mktmpdir }
  let(:db_path) { File.join(temp_dir, "test_db") }
  let(:sample_text_file) { File.join(temp_dir, "sample.txt") }
  
  before do
    # Create a sample text file for testing
    File.write(sample_text_file, "This is a sample document about machine learning and artificial intelligence.")
    
    # Stub external dependencies for faster tests
    allow_any_instance_of(Ragnar::Embedder).to receive(:embed_text).and_return(fake_embedding_for("text"))
    allow_any_instance_of(Ragnar::Indexer).to receive(:index_path).and_return({
      files_processed: 1,
      chunks_created: 1,
      errors: 0
    })
    allow_any_instance_of(Ragnar::Database).to receive(:add_documents)
    allow_any_instance_of(Ragnar::Database).to receive(:get_stats).and_return({
      with_embeddings: 1,
      total_documents: 1,
      unique_files: 1,
      total_chunks: 1,
      embedding_dims: 384
    })
  end
  
  after do
    FileUtils.rm_rf(temp_dir)
  end
  
  describe "version command" do
    it "displays the version" do
      output = capture_stdout { Ragnar::CLI.start(["version"]) }
      expect(output).to include("Ragnar v")
    end
  end
  
  describe "stats command" do
    context "with valid database" do
      before do
        allow_any_instance_of(Ragnar::Database).to receive(:get_stats).and_return({
          total_documents: 5,
          unique_files: 3,
          total_chunks: 5,
          with_embeddings: 5,
          with_reduced_embeddings: 0,
          avg_chunk_size: 150,
          embedding_dims: 384,
          reduced_dims: nil
        })
      end
      
      it "displays database statistics" do
        output = capture_stdout { Ragnar::CLI.start(["stats", "--db-path", db_path]) }
        
        expect(output).to include("Database Statistics")
        expect(output).to include("Total documents: 5")
        expect(output).to include("Unique files: 3")
        expect(output).to include("With embeddings: 5")
        expect(output).to include("Average chunk size: 150")
        expect(output).to include("Embedding dimensions: 384")
      end
    end
    
    context "with database error" do
      before do
        allow_any_instance_of(Ragnar::Database).to receive(:get_stats).and_raise("Database error")
      end
      
      it "handles database errors gracefully" do
        expect {
          capture_stdout { Ragnar::CLI.start(["stats", "--db-path", db_path]) }
        }.to raise_error(SystemExit)
      end
    end
  end
  
  describe "index command" do
    context "with valid file path" do
      it "indexes the file successfully" do
        output = capture_stdout { Ragnar::CLI.start(["index", sample_text_file, "--db-path", db_path]) }
        
        expect(output).to include("Indexing files from: #{sample_text_file}")
        expect(output).to include("Indexing complete!")
        expect(output).to include("Files processed: 1")
        expect(output).to include("Chunks created: 1")
      end
      
      it "accepts custom chunk size" do
        output = capture_stdout { 
          Ragnar::CLI.start(["index", sample_text_file, "--db-path", db_path, "--chunk-size", "500"]) 
        }
        
        expect(output).to include("Indexing complete!")
      end
    end
    
    context "with non-existent file" do
      it "shows error for missing file" do
        expect {
          capture_stdout { Ragnar::CLI.start(["index", "/non/existent/path"]) }
        }.to raise_error(SystemExit)
      end
    end
    
    context "with indexing error" do
      before do
        allow_any_instance_of(Ragnar::Indexer).to receive(:index_path).and_raise("Indexing failed")
      end
      
      it "handles indexing errors gracefully" do
        expect {
          capture_stdout { Ragnar::CLI.start(["index", sample_text_file, "--db-path", db_path]) }
        }.to raise_error(SystemExit)
      end
    end
  end
  
  describe "search command" do
    before do
      allow_any_instance_of(Ragnar::Database).to receive(:search_similar).and_return([
        {
          file_path: "sample.txt",
          chunk_index: 0,
          chunk_text: "This is a sample document about machine learning",
          distance: 0.1
        },
        {
          file_path: "another.txt", 
          chunk_index: 0,
          chunk_text: "Another document about artificial intelligence",
          distance: 0.2
        }
      ])
    end
    
    it "searches for similar documents" do
      output = capture_stdout { 
        Ragnar::CLI.start(["search", "machine learning", "--database", db_path]) 
      }
      
      expect(output).to include("Found 2 results:")
      expect(output).to include("File: sample.txt")
      expect(output).to include("File: another.txt")
      expect(output).to include("machine learning")
    end
    
    it "shows similarity scores when requested" do
      output = capture_stdout { 
        Ragnar::CLI.start(["search", "AI", "--database", db_path, "--show-scores"]) 
      }
      
      expect(output).to include("Distance: 0.1")
      expect(output).to include("Distance: 0.2")
    end
    
    it "accepts k parameter for result limit" do
      # Mock the database to return results that would be limited by k
      allow_any_instance_of(Ragnar::Database).to receive(:search_similar).and_return([
        {
          file_path: "sample.txt",
          chunk_index: 0,
          chunk_text: "This is a sample document about machine learning",
          distance: 0.1
        }
      ])
      
      output = capture_stdout { 
        Ragnar::CLI.start(["search", "AI", "--database", db_path, "-k", "5"]) 
      }
      
      # Just verify the search ran successfully with the parameter
      expect(output).to include("Found 1 results:")
    end
    
    context "with no results" do
      before do
        allow_any_instance_of(Ragnar::Database).to receive(:search_similar).and_return([])
      end
      
      it "shows no results message" do
        output = capture_stdout { 
          Ragnar::CLI.start(["search", "nonexistent", "--database", db_path]) 
        }
        
        expect(output).to include("No results found.")
      end
    end
  end
  
  describe "topics command" do
    let(:mock_topics) do
      [
        double("Topic", 
          id: 1,
          label: "Machine Learning", 
          size: 15,
          terms: ["machine", "learning", "artificial", "intelligence"],
          coherence: 0.85,
          representative_docs: ["Document about machine learning algorithms"],
          to_h: {
            id: 1,
            label: "Machine Learning",
            size: 15,
            terms: ["machine", "learning", "artificial", "intelligence"],
            coherence: 0.85
          }
        ),
        double("Topic",
          id: 2, 
          label: "Data Science",
          size: 8,
          terms: ["data", "science", "analysis", "statistics"],
          coherence: 0.72,
          representative_docs: ["Document about data analysis techniques"],
          to_h: {
            id: 2,
            label: "Data Science",
            size: 8,
            terms: ["data", "science", "analysis", "statistics"],
            coherence: 0.72
          }
        )
      ]
    end
    
    let(:mock_engine) do
      engine = double("TopicEngine")
      allow(engine).to receive(:fit).and_return(mock_topics)
      allow(engine).to receive(:instance_variable_get).with(:@cluster_ids).and_return([0, 1, 1, 0])
      engine
    end
    
    before do
      allow_any_instance_of(Ragnar::Database).to receive(:get_all_documents_with_embeddings).and_return([
        { id: "1", chunk_text: "ML doc", file_path: "ml.txt", chunk_index: 0, embedding: [0.1] * 384 },
        { id: "2", chunk_text: "Data doc", file_path: "data.txt", chunk_index: 0, embedding: [0.2] * 384 }
      ])
      allow(Ragnar::TopicModeling::Engine).to receive(:new).and_return(mock_engine)
    end
    
    it "extracts and displays topics" do
      output = capture_stdout { 
        Ragnar::CLI.start(["topics", "--db-path", db_path]) 
      }
      
      expect(output).to include("Topic Analysis Results")
      expect(output).to include("Found 2 topics:")
      expect(output).to include("Machine Learning (15 docs)")
      expect(output).to include("Data Science (8 docs)")
      expect(output).to include("machine • learning • artificial • intelligence")
    end
    
    it "accepts custom min cluster size" do
      output = capture_stdout { 
        Ragnar::CLI.start(["topics", "--db-path", db_path, "--min-cluster-size", "3"]) 
      }
      
      expect(output).to include("Topic Analysis Results")
    end
    
    it "accepts different labeling methods" do
      output = capture_stdout { 
        Ragnar::CLI.start(["topics", "--db-path", db_path, "--method", "fast"]) 
      }
      
      expect(output).to include("Topic Analysis Results")
    end
    
    context "with summarization enabled" do
      before do
        # Mock LLM for summarization
        mock_llm = double("LLM")
        allow(mock_llm).to receive(:generate).and_return("These documents discuss machine learning techniques and algorithms.")
        allow(Candle::LLM).to receive(:from_pretrained).and_return(mock_llm)
      end
      
      it "generates topic summaries" do
        output = capture_stdout { 
          Ragnar::CLI.start(["topics", "--db-path", db_path, "--summarize"]) 
        }
        
        expect(output).to include("Generating topic summaries with LLM...")
        expect(output).to include("Topic summaries generated!")
        expect(output).to include("(with LLM-generated summaries)")
      end
      
      it "accepts custom LLM model" do
        output = capture_stdout { 
          Ragnar::CLI.start([
            "topics", "--db-path", db_path, "--summarize",
            "--llm-model", "custom/model", "--gguf-file", "custom.gguf"
          ]) 
        }
        
        expect(output).to include("Topic summaries generated!")
      end
      
      context "when LLM loading fails" do
        before do
          allow(Candle::LLM).to receive(:from_pretrained).and_raise("Model not found")
        end
        
        it "handles LLM errors gracefully" do
          output = capture_stdout { 
            Ragnar::CLI.start(["topics", "--db-path", db_path, "--summarize"]) 
          }
          
          expect(output).to include("Warning: Could not generate topic summaries")
          expect(output).to include("Proceeding without summaries")
        end
      end
    end
    
    context "with no documents" do
      before do
        allow_any_instance_of(Ragnar::Database).to receive(:get_stats).and_return({
          with_embeddings: 0
        })
      end
      
      it "shows error when no documents with embeddings" do
        expect {
          capture_stdout { Ragnar::CLI.start(["topics", "--db-path", db_path]) }
        }.to raise_error(SystemExit)
      end
    end
    
    context "with export options" do
      it "exports topics to JSON" do
        # Mock file writing to avoid actual file creation
        allow(File).to receive(:write)
        
        output = capture_stdout { 
          Ragnar::CLI.start(["topics", "--db-path", db_path, "--export", "json"]) 
        }
        
        expect(output).to include("Topics exported to:")
        expect(output).to include(".json")
      end
      
      it "exports topics to HTML" do
        # Mock file writing and Thor's yes? method without warnings
        allow(File).to receive(:write)
        
        # Mock the yes? method by defining it as a no_commands block method
        Ragnar::CLI.class_eval do
          no_commands do
            def yes?(*)
              false
            end
          end
        end
        
        output = capture_stdout { 
          Ragnar::CLI.start(["topics", "--db-path", db_path, "--export", "html"]) 
        }
        
        expect(output).to include("Topics visualization exported to:")
        expect(output).to include(".html")
      end
    end
  end
  
  describe "query command" do
    let(:mock_result) do
      {
        query: "What is machine learning?",
        clarified: "What is machine learning?",
        answer: "Machine learning is a subset of artificial intelligence...",
        confidence: 85,
        sources: [
          { source_file: "ml_intro.txt" },
          { source_file: "ai_overview.txt" }
        ],
        sub_queries: ["machine learning definition", "AI subset"]
      }
    end
    
    before do
      allow_any_instance_of(Ragnar::QueryProcessor).to receive(:query).and_return(mock_result)
    end
    
    it "processes queries and shows results" do
      output = capture_stdout { 
        Ragnar::CLI.start(["query", "What is ML?", "--db-path", db_path]) 
      }
      
      expect(output).to include("Query: What is machine learning?")
      expect(output).to include("Answer:")
      expect(output).to include("Machine learning is a subset")
      expect(output).to include("Confidence: 85%")
      expect(output).to include("Sources:")
      expect(output).to include("ml_intro.txt")
    end
    
    it "shows clarified query when different" do
      mock_result[:clarified] = "What is machine learning in detail?"
      
      output = capture_stdout { 
        Ragnar::CLI.start(["query", "What is ML?", "--db-path", db_path]) 
      }
      
      expect(output).to include("Clarified: What is machine learning in detail?")
    end
    
    it "shows sub-queries in verbose mode" do
      output = capture_stdout { 
        Ragnar::CLI.start(["query", "What is ML?", "--db-path", db_path, "--verbose"]) 
      }
      
      expect(output).to include("Sub-queries used:")
      expect(output).to include("machine learning definition")
    end
    
    it "outputs JSON format when requested" do
      output = capture_stdout { 
        Ragnar::CLI.start(["query", "What is ML?", "--db-path", db_path, "--json"]) 
      }
      
      expect { JSON.parse(output) }.not_to raise_error
      expect(output).to include("\"query\"")
      expect(output).to include("\"answer\"")
    end
    
    it "accepts custom top_k parameter" do
      output = capture_stdout { 
        Ragnar::CLI.start(["query", "What is ML?", "--db-path", db_path, "--top-k", "5"]) 
      }
      
      expect(output).to include("Answer:")
    end
    
    context "with query processing error" do
      before do
        allow_any_instance_of(Ragnar::QueryProcessor).to receive(:query).and_raise("Query failed")
      end
      
      it "handles query errors gracefully" do
        expect {
          capture_stdout { Ragnar::CLI.start(["query", "What is ML?", "--db-path", db_path]) }
        }.to raise_error(SystemExit)
      end
    end
  end
  
  private
  
  def capture_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end
end
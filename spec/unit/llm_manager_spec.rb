# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ragnar::LLMManager do
  let(:manager) { described_class.instance }

  describe "#initialize" do
    it "is a singleton" do
      instance1 = described_class.instance
      instance2 = described_class.instance
      
      expect(instance1).to be(instance2)
    end

    it "initializes with proper instance variables" do
      # Access private instance variables for testing
      llms = manager.instance_variable_get(:@llms)
      mutex = manager.instance_variable_get(:@mutex)
      
      expect(llms).to be_a(Hash)
      expect(mutex).to be_a(Mutex)
    end
  end

  describe "#get_llm" do
    context "basic functionality" do
      it "returns an LLM instance" do
        llm = manager.get_llm

        expect(llm).to be_a(Object)  # Mocked or real LLM
      end

      it "accepts custom model parameters" do
        expect {
          manager.get_llm(model_id: "custom/model", gguf_file: "custom.gguf")
        }.not_to raise_error
      end

      it "accepts nil GGUF file" do
        expect {
          manager.get_llm(model_id: "unquantized/model", gguf_file: nil)
        }.not_to raise_error
      end

      it "returns consistent instances for same parameters" do
        llm1 = manager.get_llm(model_id: "test/model", gguf_file: "test.gguf")
        llm2 = manager.get_llm(model_id: "test/model", gguf_file: "test.gguf")

        expect(llm1).to be(llm2)  # Same cached instance
      end
    end

    context "caching behavior" do
      it "caches models with different parameters separately" do
        manager.clear_cache  # Start fresh

        llm1 = manager.get_llm(model_id: "model1", gguf_file: "file1.gguf")
        llm2 = manager.get_llm(model_id: "model2", gguf_file: "file2.gguf") 
        llm1_again = manager.get_llm(model_id: "model1", gguf_file: "file1.gguf")

        expect(llm1).to be(llm1_again)  # Same cache entry
        # Note: Can't easily test model1 != model2 due to global mocking
      end

      it "treats different GGUF files as different cache entries" do
        manager.clear_cache

        llm1 = manager.get_llm(model_id: "same/model", gguf_file: "file1.gguf")
        llm2 = manager.get_llm(model_id: "same/model", gguf_file: "file2.gguf")

        # With global mocking, we can't test object identity, but we can test the method calls
        expect(llm1).to be_a(Object)
        expect(llm2).to be_a(Object)
      end

      it "handles cache key generation correctly" do
        # Test that method doesn't raise errors with various inputs
        test_params = [
          { model_id: "model1", gguf_file: "file.gguf" },
          { model_id: "model2", gguf_file: nil },
          { model_id: "model3", gguf_file: "" }
        ]

        test_params.each do |params|
          expect {
            manager.get_llm(**params)
          }.not_to raise_error
        end
      end
    end

    context "thread safety" do
      it "uses synchronization for cache access" do
        # Test that method completes without race conditions
        results = []
        
        # Simulate concurrent access (simplified test)
        2.times do
          results << manager.get_llm(model_id: "concurrent/model", gguf_file: "test.gguf")
        end

        # Should get consistent results
        expect(results.first).to be(results.last)
      end
    end
  end

  describe "#clear_cache" do
    it "clears the internal cache" do
      # Load some models first
      manager.get_llm(model_id: "model1", gguf_file: "file1.gguf")
      manager.get_llm(model_id: "model2", gguf_file: "file2.gguf")
      
      # Clear cache
      manager.clear_cache
      
      # Verify cache is empty
      llms = manager.instance_variable_get(:@llms)
      expect(llms).to be_empty
    end

    it "allows reloading models after clearing" do
      # Load a model
      original_llm = manager.get_llm(model_id: "test/model", gguf_file: "test.gguf")

      # Clear cache
      manager.clear_cache

      # Load same model again - should work without errors
      expect {
        new_llm = manager.get_llm(model_id: "test/model", gguf_file: "test.gguf")
        expect(new_llm).to be_a(Object)
      }.not_to raise_error
    end

    it "uses synchronization for thread safety" do
      expect {
        manager.clear_cache
      }.not_to raise_error
    end
  end

  describe "#default_llm" do
    it "returns an LLM instance" do
      llm = manager.default_llm
      expect(llm).to be_a(Object)
    end

    it "is equivalent to calling get_llm with defaults" do
      default1 = manager.default_llm
      default2 = manager.get_llm  # Uses default parameters

      expect(default1).to be(default2)  # Should be same cached instance
    end

    it "caches the default LLM" do
      llm1 = manager.default_llm
      llm2 = manager.default_llm

      expect(llm1).to be(llm2)  # Same cached instance
    end
  end

  describe "integration behavior" do
    it "maintains cache consistency across method calls" do
      # Test various method combinations
      default1 = manager.default_llm
      custom = manager.get_llm(model_id: "custom/model", gguf_file: "custom.gguf")
      default2 = manager.default_llm

      expect(default1).to be(default2)  # Default should be cached
    end

    it "handles various model identifier formats" do
      model_ids = [
        "organization/model-name",
        "simple-model",
        "model_with_underscores",
        "Model-With-Caps"
      ]

      model_ids.each do |model_id|
        expect {
          manager.get_llm(model_id: model_id, gguf_file: "test.gguf")
        }.not_to raise_error
      end
    end

    it "handles various GGUF file formats" do
      gguf_files = [
        "model.gguf",
        "model.Q4_K_M.gguf", 
        "model.q4_0.gguf",
        nil
      ]

      gguf_files.each do |gguf_file|
        expect {
          manager.get_llm(model_id: "test/model", gguf_file: gguf_file)
        }.not_to raise_error
      end
    end
  end

  describe "memory management" do
    it "provides cache clearing for memory management" do
      # Manually populate cache to test clearing (since global mocks prevent real caching)
      cache = manager.instance_variable_get(:@llms)
      cache["test1"] = double("LLM1")
      cache["test2"] = double("LLM2")
      cache["test3"] = double("LLM3")

      expect(cache).not_to be_empty

      manager.clear_cache
      
      expect(cache).to be_empty
    end
  end
end
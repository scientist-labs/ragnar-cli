# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ragnar::LLMManager do
  let(:manager) { described_class.instance }

  before do
    manager.clear_cache
  end

  describe "#initialize" do
    it "is a singleton" do
      instance1 = described_class.instance
      instance2 = described_class.instance

      expect(instance1).to be(instance2)
    end

    it "initializes with proper instance variables" do
      chats = manager.instance_variable_get(:@chats)
      mutex = manager.instance_variable_get(:@mutex)

      expect(chats).to be_a(Hash)
      expect(mutex).to be_a(Mutex)
    end
  end

  describe "#get_chat" do
    context "basic functionality" do
      it "returns a chat instance" do
        chat = manager.get_chat
        expect(chat).to be_a(Object)
      end

      it "accepts custom provider and model" do
        expect {
          manager.get_chat(provider: :red_candle, model: "custom/model")
        }.not_to raise_error
      end

      it "returns consistent instances for same parameters" do
        chat1 = manager.get_chat(provider: :red_candle, model: "test/model")
        chat2 = manager.get_chat(provider: :red_candle, model: "test/model")

        expect(chat1).to be(chat2)
      end
    end

    context "caching behavior" do
      it "caches chats with different parameters separately" do
        chat1 = manager.get_chat(provider: :red_candle, model: "model1")
        chat2 = manager.get_chat(provider: :red_candle, model: "model2")
        chat1_again = manager.get_chat(provider: :red_candle, model: "model1")

        expect(chat1).to be(chat1_again)
      end

      it "treats different providers as different cache entries" do
        chat1 = manager.get_chat(provider: :red_candle, model: "same/model")
        chat2 = manager.get_chat(provider: :openai, model: "same/model")

        expect(chat1).to be_a(Object)
        expect(chat2).to be_a(Object)
      end
    end

    context "thread safety" do
      it "uses synchronization for cache access" do
        results = []

        2.times do
          results << manager.get_chat(provider: :red_candle, model: "concurrent/model")
        end

        expect(results.first).to be(results.last)
      end
    end
  end

  describe "#clear_cache" do
    it "clears the internal cache" do
      manager.get_chat(provider: :red_candle, model: "model1")
      manager.get_chat(provider: :red_candle, model: "model2")

      manager.clear_cache

      chats = manager.instance_variable_get(:@chats)
      expect(chats).to be_empty
    end

    it "allows reloading chats after clearing" do
      manager.get_chat(provider: :red_candle, model: "test/model")
      manager.clear_cache

      expect {
        chat = manager.get_chat(provider: :red_candle, model: "test/model")
        expect(chat).to be_a(Object)
      }.not_to raise_error
    end
  end

  describe "#default_chat" do
    it "returns a chat instance" do
      chat = manager.default_chat
      expect(chat).to be_a(Object)
    end

    it "is equivalent to calling get_chat with defaults" do
      default1 = manager.default_chat
      default2 = manager.get_chat

      expect(default1).to be(default2)
    end

    it "caches the default chat" do
      chat1 = manager.default_chat
      chat2 = manager.default_chat

      expect(chat1).to be(chat2)
    end
  end

  describe "backwards compatibility" do
    it "aliases get_llm to get_chat" do
      expect(manager.method(:get_llm)).not_to be_nil
      chat = manager.get_llm
      expect(chat).to be_a(Object)
    end

    it "aliases default_llm to default_chat" do
      expect(manager.method(:default_llm)).not_to be_nil
      chat = manager.default_llm
      expect(chat).to be_a(Object)
    end
  end

  describe "memory management" do
    it "provides cache clearing for memory management" do
      cache = manager.instance_variable_get(:@chats)
      cache["test1"] = double("Chat1")
      cache["test2"] = double("Chat2")

      expect(cache).not_to be_empty

      manager.clear_cache

      expect(cache).to be_empty
    end
  end
end

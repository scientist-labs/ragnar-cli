# frozen_string_literal: true

require "spec_helper"

RSpec.describe "CLI profile command" do
  let(:config) { Ragnar::Config.instance }

  before do
    allow(Ragnar::Config).to receive(:instance).and_return(config)
    allow(config).to receive(:llm_profiles).and_return({
      'red_candle' => { 'provider' => 'red_candle', 'model' => 'Qwen3-4B' },
      'opus' => { 'provider' => 'anthropic', 'model' => 'claude-opus-4-6' }
    })
    allow(config).to receive(:llm_profile_name).and_return('red_candle')
    allow(config).to receive(:llm_provider).and_return('red_candle')
    allow(config).to receive(:llm_model).and_return('Qwen3-4B')
    allow(config).to receive(:set_active_profile)
    allow(Ragnar::LLMManager.instance).to receive(:clear_cache)
  end

  describe "profile (no args)" do
    it "lists all profiles with active indicator" do
      output = capture_stdout do
        Ragnar::CLI.start(["profile"])
      end
      expect(output).to include("red_candle")
      expect(output).to include("opus")
      expect(output).to include("(active)")
    end
  end

  describe "profile NAME" do
    it "switches to named profile" do
      output = capture_stdout do
        Ragnar::CLI.start(["profile", "opus"])
      end
      expect(config).to have_received(:set_active_profile).with("opus")
      expect(output).to include("Switched to profile: opus")
    end

    it "clears LLM cache on switch" do
      capture_stdout do
        Ragnar::CLI.start(["profile", "opus"])
      end
      expect(Ragnar::LLMManager.instance).to have_received(:clear_cache)
    end

    it "shows error for unknown profile" do
      allow(config).to receive(:set_active_profile).and_raise(ArgumentError, "Unknown profile 'bad'")
      output = capture_stdout do
        Ragnar::CLI.start(["profile", "bad"])
      end
      expect(output).to include("Unknown profile")
    end
  end

  describe "--profile global option" do
    it "is available on query command" do
      options = Ragnar::CLI.class_options
      expect(options).to have_key(:profile)
      expect(options[:profile].aliases).to include("-p")
    end
  end
end

RSpec.describe "CLI verbose command" do
  before do
    Ragnar::CLI.class_variable_set(:@@verbose_mode, false)
  end

  it "toggles verbose mode on" do
    output = capture_stdout do
      Ragnar::CLI.start(["verbose"])
    end
    expect(output).to include("Verbose mode: on")
    expect(Ragnar::CLI.class_variable_get(:@@verbose_mode)).to be true
  end

  it "toggles verbose mode off" do
    Ragnar::CLI.class_variable_set(:@@verbose_mode, true)
    output = capture_stdout do
      Ragnar::CLI.start(["verbose"])
    end
    expect(output).to include("Verbose mode: off")
    expect(Ragnar::CLI.class_variable_get(:@@verbose_mode)).to be false
  end
end

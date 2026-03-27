# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ragnar::CLI::Umap do
  let(:config) { Ragnar::Config.instance }
  let(:model_path) { File.join(temp_dir, "umap_model.bin") }

  before do
    allow(Ragnar::Config).to receive(:instance).and_return(config)
    allow(config).to receive(:database_path).and_return(File.join(temp_dir, "test.lance"))
    allow(config).to receive(:models_dir).and_return(temp_dir)
  end

  describe "subcommand registration" do
    it "is registered as a subcommand of CLI" do
      expect(Ragnar::CLI.subcommands).to include("umap")
    end

    it "has train and apply commands" do
      commands = described_class.all_commands.keys
      expect(commands).to include("train")
      expect(commands).to include("apply")
    end
  end

  describe "train" do
    let(:mock_processor) { instance_double(Ragnar::UmapProcessor, model_path: model_path) }

    before do
      allow(Ragnar::UmapProcessor).to receive(:new).and_return(mock_processor)
    end

    context "with successful training" do
      let(:train_stats) do
        { embeddings_count: 100, original_dims: 768, reduced_dims: 50 }
      end

      before do
        allow(mock_processor).to receive(:train).and_return(train_stats)
      end

      it "trains with default parameters" do
        output = capture_stdout do
          Ragnar::CLI.start(["umap", "train"])
        end
        expect(output).to include("Training UMAP model")
        expect(output).to include("UMAP training complete!")
        expect(output).to include("Embeddings processed: 100")
      end

      it "passes custom parameters to processor" do
        expect(mock_processor).to receive(:train).with(
          n_components: 10, n_neighbors: 5, min_dist: 0.1
        ).and_return(train_stats)

        capture_stdout do
          Ragnar::CLI.start(["umap", "train", "--n-components", "10", "--n-neighbors", "5"])
        end
      end

      it "uses custom model path when specified" do
        custom_path = File.join(temp_dir, "custom_model.bin")
        expect(Ragnar::UmapProcessor).to receive(:new).with(
          hash_including(model_path: custom_path)
        ).and_return(mock_processor)

        capture_stdout do
          Ragnar::CLI.start(["umap", "train", "--model-path", custom_path])
        end
      end

      it "uses custom db path when specified" do
        custom_db = File.join(temp_dir, "custom.lance")
        expect(Ragnar::UmapProcessor).to receive(:new).with(
          hash_including(db_path: custom_db)
        ).and_return(mock_processor)

        capture_stdout do
          Ragnar::CLI.start(["umap", "train", "--db-path", custom_db])
        end
      end

      it "displays model save path" do
        output = capture_stdout do
          Ragnar::CLI.start(["umap", "train"])
        end
        expect(output).to include("Model saved to: #{model_path}")
      end
    end

    context "when training fails" do
      before do
        allow(mock_processor).to receive(:train).and_raise(RuntimeError, "LAPACK error")
      end

      it "displays error message and exits" do
        expect {
          capture_stdout do
            Ragnar::CLI.start(["umap", "train"])
          end
        }.to raise_error(SystemExit)
      end

      it "shows the error message" do
        output = capture_stdout do
          begin
            Ragnar::CLI.start(["umap", "train"])
          rescue SystemExit
            # expected
          end
        end
        expect(output).to include("Error during UMAP training")
        expect(output).to include("LAPACK error")
      end
    end
  end

  describe "apply" do
    let(:mock_processor) { instance_double(Ragnar::UmapProcessor, model_path: model_path) }

    before do
      allow(Ragnar::UmapProcessor).to receive(:new).and_return(mock_processor)
    end

    context "when model exists" do
      let(:apply_stats) do
        { processed: 100, skipped: 5, errors: 0 }
      end

      before do
        FileUtils.touch(model_path)
        allow(mock_processor).to receive(:apply).and_return(apply_stats)
      end

      it "applies the model successfully" do
        output = capture_stdout do
          Ragnar::CLI.start(["umap", "apply"])
        end
        expect(output).to include("Applying UMAP model")
        expect(output).to include("UMAP application complete!")
        expect(output).to include("Embeddings processed: 100")
        expect(output).to include("Already processed: 5")
      end

      it "passes custom batch size" do
        expect(mock_processor).to receive(:apply).with(
          batch_size: 50
        ).and_return(apply_stats)

        capture_stdout do
          Ragnar::CLI.start(["umap", "apply", "--batch-size", "50"])
        end
      end

      it "displays errors count when present" do
        allow(mock_processor).to receive(:apply).and_return(
          { processed: 90, skipped: 5, errors: 5 }
        )

        output = capture_stdout do
          Ragnar::CLI.start(["umap", "apply"])
        end
        expect(output).to include("Errors: 5")
      end

      it "does not display errors line when zero" do
        output = capture_stdout do
          Ragnar::CLI.start(["umap", "apply"])
        end
        expect(output).not_to include("Errors:")
      end
    end

    context "when model does not exist" do
      it "exits with error message" do
        non_existent = File.join(temp_dir, "no_such_model.bin")

        expect {
          capture_stdout do
            Ragnar::CLI.start(["umap", "apply", "--model-path", non_existent])
          end
        }.to raise_error(SystemExit)
      end

      it "suggests running train first" do
        non_existent = File.join(temp_dir, "no_such_model.bin")

        output = capture_stdout do
          begin
            Ragnar::CLI.start(["umap", "apply", "--model-path", non_existent])
          rescue SystemExit
            # expected
          end
        end
        expect(output).to include("UMAP model not found")
        expect(output).to include("ragnar umap train")
      end
    end

    context "when apply fails" do
      before do
        FileUtils.touch(model_path)
        allow(mock_processor).to receive(:apply).and_raise(RuntimeError, "database error")
      end

      it "displays error and exits" do
        output = capture_stdout do
          begin
            Ragnar::CLI.start(["umap", "apply"])
          rescue SystemExit
            # expected
          end
        end
        expect(output).to include("Error applying UMAP")
        expect(output).to include("database error")
      end
    end
  end

  describe "help" do
    it "shows umap subcommand help" do
      output = capture_stdout do
        Ragnar::CLI.start(["umap", "help"])
      end
      expect(output).to include("train")
      expect(output).to include("apply")
    end
  end
end

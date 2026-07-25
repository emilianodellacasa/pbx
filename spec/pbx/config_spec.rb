# frozen_string_literal: true

require "tempfile"

RSpec.describe Pbx::Config do
  subject(:load) { described_class.load(cli: cli_opts) }

  let(:cli_opts) { {user: "admin", secret: "s3cret"} }

  describe "defaults" do
    it "uses 127.0.0.1 as default host" do
      expect(load.host).to eq("127.0.0.1")
    end

    it "uses 5038 as default port" do
      expect(load.port).to eq(5038)
    end

    it "uses 'default' as default context" do
      expect(load.context).to eq("default")
    end
  end

  describe "CLI flag precedence" do
    let(:cli_opts) { {host: "10.0.0.1", port: 5039, user: "u", secret: "p"} }

    it "uses CLI host over default" do
      expect(load.host).to eq("10.0.0.1")
    end

    it "uses CLI port over default" do
      expect(load.port).to eq(5039)
    end
  end

  describe "YAML config" do
    let(:yaml_content) do
      <<~YAML
        host: pbx.local
        port: 5040
        user: yamladmin
        secret: yamlsecret
        context: from-internal
      YAML
    end

    let(:yaml_file) do
      Tempfile.new(["pbx_test", ".yml"]).tap do |f|
        f.write(yaml_content)
        f.flush
      end
    end

    after { yaml_file.unlink }

    let(:cli_opts) { {config: yaml_file.path} }

    it "loads host from YAML" do
      expect(load.host).to eq("pbx.local")
    end

    it "loads user from YAML" do
      expect(load.user).to eq("yamladmin")
    end

    it "loads context from YAML" do
      expect(load.context).to eq("from-internal")
    end

    context "when CLI flag overrides YAML" do
      let(:cli_opts) { {config: yaml_file.path, host: "override.local"} }

      it "prefers CLI flag" do
        expect(load.host).to eq("override.local")
      end

      it "still loads non-overridden YAML values" do
        expect(load.user).to eq("yamladmin")
      end
    end
  end

  describe "#complete?" do
    context "when user and secret are present" do
      let(:cli_opts) { {user: "admin", secret: "s3cret"} }

      it "returns true" do
        expect(load.complete?).to be true
      end
    end

    context "when user is missing" do
      let(:cli_opts) { {secret: "pass"} }

      it "returns false" do
        expect(load.complete?).to be false
      end

      it "does not raise" do
        expect { load }.not_to raise_error
      end
    end

    context "when secret is missing" do
      let(:cli_opts) { {user: "admin"} }

      it "returns false" do
        expect(load.complete?).to be false
      end
    end

    context "when both are missing" do
      let(:cli_opts) { {} }

      it "returns false" do
        expect(load.complete?).to be false
      end
    end
  end

  describe "YAML file not found" do
    let(:cli_opts) { {config: "/nonexistent/path.yml"} }

    it "raises Config::Error" do
      expect { load }.to raise_error(Pbx::Config::Error, /not found/)
    end
  end
end

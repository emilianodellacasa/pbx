# frozen_string_literal: true

RSpec.describe Pbx::Views::Header do
  let(:config) do
    Pbx::Config::Value.new(
      host: "pbx.test", port: 5038, user: "u", secret: "p",
      context: "default", reconnect_backoff: [1]
    )
  end

  let(:state) do
    double("App",
           config: config, width: 80, status: :connecting,
           error: nil, extensions: {})
  end

  subject(:output) { described_class.call(state) }

  it "returns a String" do
    expect(output).to be_a(String)
  end

  it "includes the host" do
    expect(output).to include("pbx.test")
  end

  context "when connected" do
    before { allow(state).to receive(:status).and_return(:connected) }

    it "includes connected indicator" do
      expect(output).to include("pbx.test")
    end
  end

  context "when connection lost" do
    before do
      allow(state).to receive(:status).and_return(:lost)
      allow(state).to receive(:error).and_return("timeout")
    end

    it "includes the error message" do
      expect(output).to include("timeout")
    end
  end
end

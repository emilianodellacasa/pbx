# frozen_string_literal: true

RSpec.describe Pbx::Views::InfoModal do
  let(:state) do
    double("App", width: 80, height: 24)
  end

  subject(:output) { described_class.call(state) }

  it "returns a String" do
    expect(output).to be_a(String)
  end

  it "includes the software name" do
    expect(output).to include("PBX Monitor")
  end

  it "includes the author name" do
    expect(output).to include("Emiliano Della Casa")
  end

  it "includes the GitHub URL" do
    expect(output).to include("github.com/emilianodellacasa/pbx")
  end

  it "includes the version" do
    expect(output).to include(Pbx::VERSION)
  end

  it "includes a close hint" do
    expect(output.downcase).to include("press any key")
  end
end

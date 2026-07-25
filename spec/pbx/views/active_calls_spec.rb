# frozen_string_literal: true

RSpec.describe Pbx::Views::ActiveCalls do
  describe ".short_channel" do
    it "returns — for nil" do
      expect(described_class.short_channel(nil)).to eq("—")
    end

    it "strips the SIP/ prefix and the random suffix" do
      expect(described_class.short_channel("SIP/alice-00000001")).to eq("alice")
    end

    it "strips the PJSIP/ prefix and the random suffix" do
      expect(described_class.short_channel("PJSIP/endpoint-00000001")).to eq("endpoint")
    end

    it "is case-insensitive on the prefix" do
      expect(described_class.short_channel("pjsip/alice-00000001")).to eq("alice")
    end

    it "returns the channel unchanged for unrecognised types" do
      expect(described_class.short_channel("Local/s@default-00000001")).to eq("Local/s@default")
    end
  end

  describe ".render" do
    it "returns a String" do
      calls = {}
      expect(described_class.render(calls, 80, 5)).to be_a(String)
    end

    it "includes the call count in the title" do
      call = Pbx::Call.new(
        uniqueid: "1", channel: "SIP/alice-00000001",
        caller_id: "101", caller_name: "Alice",
        connected_to: nil, state: "Ring", started_at: Time.now,
        outcome: nil, held: false, dialplan_app: nil, dialplan_exten: nil
      )
      output = described_class.render({"1" => call}, 80, 5)
      expect(output).to include("Active Calls (1)")
    end
  end
end

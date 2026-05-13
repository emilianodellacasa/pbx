# frozen_string_literal: true

RSpec.describe Pbx::Views::ExtensionTable do
  let(:peers) do
    {
      "alice" => Pbx::Peer.new(id: "alice", name: "alice", ip_address: "192.168.1.10",
                               ip_port: 5060, status: "registered", type: "friend",
                               dynamic: "yes", user_agent: "Linphone", rtt_ms: 3,
                               last_change_at: nil),
      "bob"   => Pbx::Peer.new(id: "bob", name: "bob", ip_address: nil,
                               ip_port: nil, status: "unreachable", type: "friend",
                               dynamic: "yes", user_agent: nil, rtt_ms: nil,
                               last_change_at: Time.now - 30)
    }
  end

  describe ".build" do
    it "returns a Bubbles::Table" do
      expect(described_class.build(peers, 20)).to be_a(Bubbles::Table)
    end
  end

  describe ".render_empty" do
    it "returns a String" do
      expect(described_class.render_empty).to be_a(String)
    end

    it "mentions SIP peers" do
      expect(described_class.render_empty.downcase).to include("sip")
    end
  end

  describe ".colorized_status" do
    it "renders Registered label for registered status" do
      expect(described_class.colorized_status("registered")).to include("Registered")
    end

    it "renders Unreachable label for unreachable status" do
      expect(described_class.colorized_status("unreachable")).to include("Unreachable")
    end
  end

  describe ".since" do
    it "returns '—' for nil" do
      expect(described_class.since(nil)).to eq("—")
    end

    it "returns 'Just now' for very recent times" do
      expect(described_class.since(Time.now - 1)).to eq("Just now")
    end

    it "returns seconds for recent times" do
      expect(described_class.since(Time.now - 30)).to match(/\d+s ago/)
    end

    it "returns minutes for older times" do
      expect(described_class.since(Time.now - 130)).to match(/\d+m ago/)
    end
  end
end

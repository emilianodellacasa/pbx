# frozen_string_literal: true

RSpec.describe Pbx::Views::ExtensionTable do
  let(:extensions) do
    {
      "SIP/1001" => Pbx::Peer.new(id: "SIP/1001", extension: "1001", context: "default",
                                  label: "Alice", status_code: "0", last_change_at: nil),
      "SIP/1002" => Pbx::Peer.new(id: "SIP/1002", extension: "1002", context: "default",
                                  label: "Bob", status_code: "1", last_change_at: Time.now - 30)
    }
  end

  describe ".build" do
    it "returns a Bubbles::Table" do
      table = described_class.build(extensions, 20)
      expect(table).to be_a(Bubbles::Table)
    end
  end

  describe ".render_empty" do
    it "returns a String" do
      expect(described_class.render_empty).to be_a(String)
    end

    it "mentions extensions" do
      expect(described_class.render_empty.downcase).to include("extension")
    end
  end

  describe ".colorized_status" do
    it "includes the human-readable status label" do
      rendered = described_class.colorized_status("0")
      expect(rendered).to include("Idle")
    end

    it "includes the human-readable In Use label" do
      rendered = described_class.colorized_status("1")
      expect(rendered).to include("In Use")
    end
  end

  describe ".since" do
    it "returns '—' for nil" do
      expect(described_class.since(nil)).to eq("—")
    end

    it "returns 'just now' for very recent times" do
      expect(described_class.since(Time.now - 1)).to eq("just now")
    end

    it "returns seconds for recent times" do
      expect(described_class.since(Time.now - 30)).to match(/\d+s ago/)
    end

    it "returns minutes for older times" do
      expect(described_class.since(Time.now - 130)).to match(/\d+m ago/)
    end
  end
end

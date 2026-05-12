# frozen_string_literal: true

RSpec.describe Pbx::AmiBridge do
  let(:config) do
    Pbx::Config::Value.new(
      host: "127.0.0.1", port: 5038, user: "admin", secret: "s3cret",
      context: "default", reconnect_backoff: [1, 2, 5]
    )
  end

  let(:fake_client) { FakeAmiClient.new(peers: sip_peers_data) }
  subject(:bridge)  { described_class.new(config, client: fake_client) }

  let(:sip_peers_data) do
    [
      { "ObjectName" => "1001", "Status" => "OK", "Description" => "Alice" },
      { "ObjectName" => "1002", "Status" => "UNREACHABLE", "Description" => "Bob" }
    ]
  end

  describe "#connect_and_login" do
    it "connects and logs in successfully" do
      expect { bridge.connect_and_login }.not_to raise_error
    end

    it "marks the client as connected" do
      bridge.connect_and_login
      expect(fake_client.connected).to be true
    end
  end

  describe "#discover_peers" do
    before { bridge.connect_and_login }

    it "returns Peer objects from sip_peers" do
      peers = bridge.discover_peers
      expect(peers).to all(be_a(Pbx::Peer))
    end

    it "maps ObjectName to extension" do
      peers = bridge.discover_peers
      extensions = peers.map(&:extension)
      expect(extensions).to include("1001", "1002")
    end

    it "maps OK status to code '0' (Idle)" do
      peers = bridge.discover_peers
      alice = peers.find { |p| p.extension == "1001" }
      expect(alice.status_code).to eq("0")
    end

    it "maps UNREACHABLE status to code '3' (Unavailable)" do
      peers = bridge.discover_peers
      bob = peers.find { |p| p.extension == "1002" }
      expect(bob.status_code).to eq("3")
    end
  end

  describe "#next_event" do
    before { bridge.connect_and_login }

    it "translates ExtensionStatus event to LineStatusChanged" do
      event = fake_client.inject_event("ExtensionStatus",
                                       "Exten" => "1001", "StatusText" => "InUse")
      bridge.instance_variable_get(:@queue).push({ type: :event, event: event })

      msg = bridge.next_event
      expect(msg).to be_a(Pbx::Messages::LineStatusChanged)
      expect(msg.peer_id).to eq("1001")
      expect(msg.status_code).to eq("1")
    end

    it "translates PeerStatus Registered to Idle" do
      event = fake_client.inject_event("PeerStatus",
                                       "Peer" => "SIP/1001", "PeerStatus" => "Registered")
      bridge.instance_variable_get(:@queue).push({ type: :event, event: event })

      msg = bridge.next_event
      expect(msg).to be_a(Pbx::Messages::LineStatusChanged)
      expect(msg.status_code).to eq("0")
    end

    it "returns nil sentinel as nil" do
      bridge.instance_variable_get(:@queue).push(Pbx::AmiBridge::SENTINEL)
      expect(bridge.next_event).to be_nil
    end

    it "skips unknown events and returns next valid one" do
      # Push an unknown event first
      event_unknown = fake_client.inject_event("SomeUnknownEvent", "Foo" => "bar")
      event_known   = fake_client.inject_event("ExtensionStatus",
                                               "Exten" => "1001", "StatusText" => "Idle")

      queue = bridge.instance_variable_get(:@queue)
      queue.push({ type: :event, event: event_unknown })
      queue.push({ type: :event, event: event_known })

      msg = bridge.next_event
      expect(msg).to be_a(Pbx::Messages::LineStatusChanged)
      expect(msg.status_code).to eq("0")
    end
  end

  describe "#shutdown" do
    it "pushes SENTINEL into the queue" do
      bridge.shutdown
      sentinel = bridge.instance_variable_get(:@queue).pop(true)
      expect(sentinel).to eq(Pbx::AmiBridge::SENTINEL)
    end
  end
end

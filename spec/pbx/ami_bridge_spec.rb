# frozen_string_literal: true

RSpec.describe Pbx::AmiBridge do
  let(:config) do
    Pbx::Config::Value.new(
      host: "127.0.0.1", port: 5038, user: "admin", secret: "s3cret",
      context: "default", reconnect_backoff: [1, 2, 5]
    )
  end

  let(:sip_peers_data) do
    [
      { "ObjectName" => "alice", "Status" => "OK (3 ms)", "IPaddress" => "192.168.1.10",
        "IPport" => "5060", "Type" => "friend", "Dynamic" => "yes", "SIP-Useragent" => "Linphone" },
      { "ObjectName" => "bob", "Status" => "UNREACHABLE", "IPaddress" => "-none-",
        "IPport" => "0", "Type" => "friend", "Dynamic" => "yes", "SIP-Useragent" => nil }
    ]
  end

  let(:fake_client) { FakeAmiClient.new(peers: sip_peers_data) }
  subject(:bridge)  { described_class.new(config, client: fake_client) }

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

    it "returns Peer objects" do
      expect(bridge.discover_peers).to all(be_a(Pbx::Peer))
    end

    it "maps ObjectName to peer name" do
      names = bridge.discover_peers.map(&:name)
      expect(names).to include("alice", "bob")
    end

    it "parses IP address for registered peers" do
      alice = bridge.discover_peers.find { |p| p.name == "alice" }
      expect(alice.ip_address).to eq("192.168.1.10")
    end

    it "sets ip_address to nil when not registered" do
      bob = bridge.discover_peers.find { |p| p.name == "bob" }
      expect(bob.ip_address).to be_nil
    end

    it "normalises OK status to 'registered'" do
      alice = bridge.discover_peers.find { |p| p.name == "alice" }
      expect(alice.status).to eq("registered")
    end

    it "normalises UNREACHABLE status to 'unreachable'" do
      bob = bridge.discover_peers.find { |p| p.name == "bob" }
      expect(bob.status).to eq("unreachable")
    end

    it "extracts RTT from OK status string" do
      alice = bridge.discover_peers.find { |p| p.name == "alice" }
      expect(alice.rtt_ms).to eq(3)
    end

    it "sets rtt_ms to nil when unreachable" do
      bob = bridge.discover_peers.find { |p| p.name == "bob" }
      expect(bob.rtt_ms).to be_nil
    end
  end

  describe "#next_event" do
    before { bridge.connect_and_login }

    it "translates PeerStatus Registered event to PeerStatusChanged" do
      event = fake_client.inject_event("PeerStatus",
                                       "ChannelType" => "SIP",
                                       "Peer"        => "SIP/alice",
                                       "PeerStatus"  => "Registered",
                                       "Address"     => "192.168.1.10:5060")
      bridge.instance_variable_get(:@queue).push({ type: :event, event: event })

      msg = bridge.next_event
      expect(msg).to be_a(Pbx::Messages::PeerStatusChanged)
      expect(msg.peer_name).to eq("alice")
      expect(msg.status).to eq("registered")
      expect(msg.ip_address).to eq("192.168.1.10")
      expect(msg.ip_port).to eq(5060)
    end

    it "translates PeerStatus Unreachable event" do
      event = fake_client.inject_event("PeerStatus",
                                       "ChannelType" => "SIP",
                                       "Peer"        => "SIP/bob",
                                       "PeerStatus"  => "Unreachable",
                                       "Time"        => "2000")
      bridge.instance_variable_get(:@queue).push({ type: :event, event: event })

      msg = bridge.next_event
      expect(msg).to be_a(Pbx::Messages::PeerStatusChanged)
      expect(msg.peer_name).to eq("bob")
      expect(msg.status).to eq("unreachable")
      expect(msg.rtt_ms).to eq(2000)
    end

    it "ignores non-SIP PeerStatus events" do
      event_pjsip = fake_client.inject_event("PeerStatus",
                                             "ChannelType" => "PJSIP",
                                             "Peer"        => "PJSIP/carol",
                                             "PeerStatus"  => "Registered")
      event_sip   = fake_client.inject_event("PeerStatus",
                                             "ChannelType" => "SIP",
                                             "Peer"        => "SIP/alice",
                                             "PeerStatus"  => "Registered",
                                             "Address"     => "10.0.0.1:5060")

      queue = bridge.instance_variable_get(:@queue)
      queue.push({ type: :event, event: event_pjsip })
      queue.push({ type: :event, event: event_sip })

      msg = bridge.next_event
      expect(msg.peer_name).to eq("alice")
    end

    it "returns nil on shutdown sentinel" do
      bridge.instance_variable_get(:@queue).push(Pbx::AmiBridge::SENTINEL)
      expect(bridge.next_event).to be_nil
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

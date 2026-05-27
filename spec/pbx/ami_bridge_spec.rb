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
      {"ObjectName" => "alice", "Status" => "OK (3 ms)", "IPaddress" => "192.168.1.10",
       "IPport" => "5060", "Type" => "friend", "Dynamic" => "yes", "SIP-Useragent" => "Linphone"},
      {"ObjectName" => "bob", "Status" => "UNREACHABLE", "IPaddress" => "-none-",
       "IPport" => "0", "Type" => "friend", "Dynamic" => "yes", "SIP-Useragent" => nil}
    ]
  end

  let(:fake_client) { FakeAmiClient.new(peers: sip_peers_data) }
  subject(:bridge) { described_class.new(config, client: fake_client) }

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

    context "with PJSIP endpoints" do
      let(:pjsip_data) do
        [
          {"ObjectName" => "carol", "DeviceState" => "Not in use"},
          {"ObjectName" => "dave", "DeviceState" => "Unavailable"}
        ]
      end

      subject(:bridge) { described_class.new(config, client: FakeAmiClient.new(peers: sip_peers_data, pjsip_endpoints: pjsip_data)) }

      before { bridge.connect_and_login }

      it "includes both SIP and PJSIP peers" do
        names = bridge.discover_peers.map(&:name)
        expect(names).to include("alice", "bob", "carol", "dave")
      end

      it "marks PJSIP endpoints with type PJSIP" do
        carol = bridge.discover_peers.find { |p| p.name == "carol" }
        expect(carol.type).to eq("PJSIP")
      end

      it "maps Not in use DeviceState to registered" do
        carol = bridge.discover_peers.find { |p| p.name == "carol" }
        expect(carol.status).to eq("registered")
      end

      it "maps Unavailable DeviceState to unreachable" do
        dave = bridge.discover_peers.find { |p| p.name == "dave" }
        expect(dave.status).to eq("unreachable")
      end

      it "sets ip_address to nil for PJSIP endpoints" do
        carol = bridge.discover_peers.find { |p| p.name == "carol" }
        expect(carol.ip_address).to be_nil
      end
    end
  end

  describe "#next_event" do
    before { bridge.connect_and_login }

    it "translates PeerStatus Registered event to PeerStatusChanged" do
      event = fake_client.inject_event("PeerStatus",
        "ChannelType" => "SIP",
        "Peer" => "SIP/alice",
        "PeerStatus" => "Registered",
        "Address" => "192.168.1.10:5060")
      bridge.instance_variable_get(:@queue).push({type: :event, event: event})

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
        "Peer" => "SIP/bob",
        "PeerStatus" => "Unreachable",
        "Time" => "2000")
      bridge.instance_variable_get(:@queue).push({type: :event, event: event})

      msg = bridge.next_event
      expect(msg).to be_a(Pbx::Messages::PeerStatusChanged)
      expect(msg.peer_name).to eq("bob")
      expect(msg.status).to eq("unreachable")
      expect(msg.rtt_ms).to eq(2000)
    end

    it "ignores PeerStatus events for unknown channel types (e.g. IAX2)" do
      event_iax = fake_client.inject_event("PeerStatus",
        "ChannelType" => "IAX2",
        "Peer" => "IAX2/carol",
        "PeerStatus" => "Registered")
      event_sip = fake_client.inject_event("PeerStatus",
        "ChannelType" => "SIP",
        "Peer" => "SIP/alice",
        "PeerStatus" => "Registered",
        "Address" => "10.0.0.1:5060")

      queue = bridge.instance_variable_get(:@queue)
      queue.push({type: :event, event: event_iax})
      queue.push({type: :event, event: event_sip})

      msg = bridge.next_event
      expect(msg.peer_name).to eq("alice")
    end

    it "returns nil on shutdown sentinel" do
      bridge.instance_variable_get(:@queue).push(Pbx::AmiBridge::SENTINEL)
      expect(bridge.next_event).to be_nil
    end

    it "translates Newchannel to CallStarted for SIP channels" do
      event = fake_client.inject_event("Newchannel",
        "Channel" => "SIP/alice-00000001",
        "Uniqueid" => "1234567890.1",
        "CallerIDNum" => "101",
        "CallerIDName" => "Alice",
        "ChannelStateDesc" => "Ring")
      bridge.instance_variable_get(:@queue).push({type: :event, event: event})

      msg = bridge.next_event
      expect(msg).to be_a(Pbx::Messages::CallStarted)
      expect(msg.uniqueid).to eq("1234567890.1")
      expect(msg.channel).to eq("SIP/alice-00000001")
      expect(msg.caller_id).to eq("101")
      expect(msg.caller_name).to eq("Alice")
      expect(msg.state).to eq("Ring")
    end

    it "ignores Newchannel for non-SIP/PJSIP channels (e.g. Local)" do
      event_local = fake_client.inject_event("Newchannel",
        "Channel" => "Local/s@default-00000001",
        "Uniqueid" => "999")
      event_sip = fake_client.inject_event("PeerStatus",
        "ChannelType" => "SIP",
        "Peer" => "SIP/alice",
        "PeerStatus" => "Registered",
        "Address" => "10.0.0.1:5060")
      queue = bridge.instance_variable_get(:@queue)
      queue.push({type: :event, event: event_local})
      queue.push({type: :event, event: event_sip})

      msg = bridge.next_event
      expect(msg).to be_a(Pbx::Messages::PeerStatusChanged)
    end

    it "translates Hangup to CallEnded for SIP channels" do
      event = fake_client.inject_event("Hangup",
        "Channel" => "SIP/alice-00000001",
        "Uniqueid" => "1234567890.1")
      bridge.instance_variable_get(:@queue).push({type: :event, event: event})

      msg = bridge.next_event
      expect(msg).to be_a(Pbx::Messages::CallEnded)
      expect(msg.uniqueid).to eq("1234567890.1")
    end

    it "translates DialBegin to CallStateChanged with Dialing state" do
      event = fake_client.inject_event("DialBegin",
        "Uniqueid" => "1234567890.1",
        "DestCallerIDNum" => "102")
      bridge.instance_variable_get(:@queue).push({type: :event, event: event})

      msg = bridge.next_event
      expect(msg).to be_a(Pbx::Messages::CallStateChanged)
      expect(msg.uniqueid).to eq("1234567890.1")
      expect(msg.state).to eq("Dialing")
      expect(msg.connected_to).to eq("102")
    end

    it "translates DialEnd to DialCompleted" do
      event = fake_client.inject_event("DialEnd",
        "Uniqueid" => "1234567890.1",
        "DialStatus" => "BUSY")
      bridge.instance_variable_get(:@queue).push({type: :event, event: event})

      msg = bridge.next_event
      expect(msg).to be_a(Pbx::Messages::DialCompleted)
      expect(msg.uniqueid).to eq("1234567890.1")
      expect(msg.dial_status).to eq("BUSY")
    end

    it "translates Hold to CallHeld" do
      event = fake_client.inject_event("Hold", "Uniqueid" => "1234567890.1")
      bridge.instance_variable_get(:@queue).push({type: :event, event: event})

      msg = bridge.next_event
      expect(msg).to be_a(Pbx::Messages::CallHeld)
      expect(msg.uniqueid).to eq("1234567890.1")
    end

    it "translates MusicOnHoldStart to CallHeld" do
      event = fake_client.inject_event("MusicOnHoldStart",
        "Uniqueid" => "1234567890.1",
        "Class" => "default")
      bridge.instance_variable_get(:@queue).push({type: :event, event: event})

      msg = bridge.next_event
      expect(msg).to be_a(Pbx::Messages::CallHeld)
    end

    it "translates Unhold to CallUnheld" do
      event = fake_client.inject_event("Unhold", "Uniqueid" => "1234567890.1")
      bridge.instance_variable_get(:@queue).push({type: :event, event: event})

      msg = bridge.next_event
      expect(msg).to be_a(Pbx::Messages::CallUnheld)
      expect(msg.uniqueid).to eq("1234567890.1")
    end

    it "translates Newexten to CallDialplanUpdate for non-noise apps" do
      event = fake_client.inject_event("Newexten",
        "Uniqueid" => "1234567890.1",
        "Context" => "from-internal",
        "Extension" => "102",
        "Application" => "Dial",
        "AppData" => "SIP/102,30")
      bridge.instance_variable_get(:@queue).push({type: :event, event: event})

      msg = bridge.next_event
      expect(msg).to be_a(Pbx::Messages::CallDialplanUpdate)
      expect(msg.uniqueid).to eq("1234567890.1")
      expect(msg.application).to eq("Dial")
      expect(msg.exten).to eq("102")
      expect(msg.context).to eq("from-internal")
    end

    it "drops Newexten for noise applications" do
      event_noise = fake_client.inject_event("Newexten",
        "Uniqueid" => "1234567890.1",
        "Application" => "Set",
        "Extension" => "s")
      event_real = fake_client.inject_event("Newexten",
        "Uniqueid" => "1234567890.1",
        "Context" => "from-internal",
        "Extension" => "102",
        "Application" => "Dial")
      queue = bridge.instance_variable_get(:@queue)
      queue.push({type: :event, event: event_noise})
      queue.push({type: :event, event: event_real})

      msg = bridge.next_event
      expect(msg).to be_a(Pbx::Messages::CallDialplanUpdate)
      expect(msg.application).to eq("Dial")
    end

    it "translates Newchannel to CallStarted for PJSIP channels" do
      event = fake_client.inject_event("Newchannel",
        "Channel" => "PJSIP/carol-00000001",
        "Uniqueid" => "1234567890.2",
        "CallerIDNum" => "201",
        "CallerIDName" => "Carol",
        "ChannelStateDesc" => "Ring")
      bridge.instance_variable_get(:@queue).push({type: :event, event: event})

      msg = bridge.next_event
      expect(msg).to be_a(Pbx::Messages::CallStarted)
      expect(msg.channel).to eq("PJSIP/carol-00000001")
    end

    it "translates Hangup to CallEnded for PJSIP channels" do
      event = fake_client.inject_event("Hangup",
        "Channel" => "PJSIP/carol-00000001",
        "Uniqueid" => "1234567890.2")
      bridge.instance_variable_get(:@queue).push({type: :event, event: event})

      msg = bridge.next_event
      expect(msg).to be_a(Pbx::Messages::CallEnded)
    end

    it "translates PJSIP PeerStatus Reachable to PeerStatusChanged" do
      event = fake_client.inject_event("PeerStatus",
        "ChannelType" => "PJSIP",
        "Peer" => "PJSIP/carol",
        "PeerStatus" => "Reachable")
      bridge.instance_variable_get(:@queue).push({type: :event, event: event})

      msg = bridge.next_event
      expect(msg).to be_a(Pbx::Messages::PeerStatusChanged)
      expect(msg.peer_name).to eq("carol")
      expect(msg.status).to eq("registered")
    end

    it "translates PJSIP PeerStatus Unreachable to PeerStatusChanged" do
      event = fake_client.inject_event("PeerStatus",
        "ChannelType" => "PJSIP",
        "Peer" => "PJSIP/carol",
        "PeerStatus" => "Unreachable")
      bridge.instance_variable_get(:@queue).push({type: :event, event: event})

      msg = bridge.next_event
      expect(msg).to be_a(Pbx::Messages::PeerStatusChanged)
      expect(msg.status).to eq("unreachable")
    end

    it "translates ChannelStateChange to CallStateChanged for PJSIP channels" do
      event = fake_client.inject_event("ChannelStateChange",
        "Channel" => "PJSIP/carol-00000001",
        "Uniqueid" => "1234567890.2",
        "ChannelStateDesc" => "Up",
        "ConnectedLineNum" => "102")
      bridge.instance_variable_get(:@queue).push({type: :event, event: event})

      msg = bridge.next_event
      expect(msg).to be_a(Pbx::Messages::CallStateChanged)
      expect(msg.state).to eq("Up")
    end

    it "translates ChannelStateChange to CallStateChanged for SIP channels" do
      event = fake_client.inject_event("ChannelStateChange",
        "Channel" => "SIP/alice-00000001",
        "Uniqueid" => "1234567890.1",
        "ChannelStateDesc" => "Up",
        "ConnectedLineNum" => "102")
      bridge.instance_variable_get(:@queue).push({type: :event, event: event})

      msg = bridge.next_event
      expect(msg).to be_a(Pbx::Messages::CallStateChanged)
      expect(msg.uniqueid).to eq("1234567890.1")
      expect(msg.state).to eq("Up")
      expect(msg.connected_to).to eq("102")
    end
  end

  describe "#discover_queues" do
    let(:queue_data) do
      [
        {
          "Queue" => "supporto", "Strategy" => "ringall",
          "Calls" => "2", "Completed" => "50", "Abandoned" => "3", "Holdtime" => "45",
          "members" => [
            {"Location" => "SIP/201", "Name" => "Alice", "Status" => "1", "Paused" => "0"},
            {"Location" => "SIP/202", "Name" => "Bob", "Status" => "2", "Paused" => "1"}
          ]
        },
        {
          "Queue" => "vendite", "Strategy" => "leastrecent",
          "Calls" => "0", "Completed" => "20", "Abandoned" => "1", "Holdtime" => "30",
          "members" => []
        }
      ]
    end

    subject(:bridge) { described_class.new(config, client: FakeAmiClient.new(queues: queue_data)) }

    before { bridge.connect_and_login }

    it "returns a Hash of CallQueue objects keyed by name" do
      result = bridge.discover_queues
      expect(result).to be_a(Hash)
      expect(result.keys).to contain_exactly("supporto", "vendite")
      expect(result.values).to all(be_a(Pbx::CallQueue))
    end

    it "populates queue fields" do
      q = bridge.discover_queues["supporto"]
      expect(q.strategy).to eq("ringall")
      expect(q.calls_waiting).to eq(2)
      expect(q.completed).to eq(50)
      expect(q.abandoned).to eq(3)
      expect(q.holdtime).to eq(45)
    end

    it "attaches members to the queue" do
      members = bridge.discover_queues["supporto"].members
      expect(members.keys).to contain_exactly("SIP/201", "SIP/202")
    end

    it "normalises member status from AMI numeric code" do
      alice = bridge.discover_queues["supporto"].members["SIP/201"]
      expect(alice.status).to eq("not_in_use")
    end

    it "sets paused flag from AMI Paused header" do
      bob = bridge.discover_queues["supporto"].members["SIP/202"]
      expect(bob.paused).to be true
    end

    it "returns empty hash on empty response" do
      bridge2 = described_class.new(config, client: FakeAmiClient.new(queues: []))
      bridge2.connect_and_login
      expect(bridge2.discover_queues).to eq({})
    end
  end

  describe "#next_event (queue events)" do
    before { bridge.connect_and_login }

    it "translates QueueCallerJoin to QueueCallerCountChanged" do
      event = fake_client.inject_event("QueueCallerJoin",
        "Queue" => "supporto", "Count" => "3")
      bridge.instance_variable_get(:@queue).push({type: :event, event: event})

      msg = bridge.next_event
      expect(msg).to be_a(Pbx::Messages::QueueCallerCountChanged)
      expect(msg.queue).to eq("supporto")
      expect(msg.count).to eq(3)
    end

    it "translates QueueCallerLeave to QueueCallerCountChanged" do
      event = fake_client.inject_event("QueueCallerLeave",
        "Queue" => "supporto", "Count" => "1")
      bridge.instance_variable_get(:@queue).push({type: :event, event: event})

      msg = bridge.next_event
      expect(msg).to be_a(Pbx::Messages::QueueCallerCountChanged)
      expect(msg.count).to eq(1)
    end

    it "translates QueueCallerAbandon to QueueCallerAbandoned" do
      event = fake_client.inject_event("QueueCallerAbandon",
        "Queue" => "supporto")
      bridge.instance_variable_get(:@queue).push({type: :event, event: event})

      msg = bridge.next_event
      expect(msg).to be_a(Pbx::Messages::QueueCallerAbandoned)
      expect(msg.queue).to eq("supporto")
    end

    it "translates QueueMemberStatus to QueueMemberUpdated" do
      event = fake_client.inject_event("QueueMemberStatus",
        "Queue" => "supporto",
        "Location" => "SIP/201",
        "Name" => "Alice",
        "Status" => "2",
        "Paused" => "0")
      bridge.instance_variable_get(:@queue).push({type: :event, event: event})

      msg = bridge.next_event
      expect(msg).to be_a(Pbx::Messages::QueueMemberUpdated)
      expect(msg.queue).to eq("supporto")
      expect(msg.interface).to eq("SIP/201")
      expect(msg.status).to eq("in_use")
      expect(msg.paused).to be false
    end

    it "translates QueueMemberPause to QueueMemberUpdated with nil status" do
      event = fake_client.inject_event("QueueMemberPause",
        "Queue" => "supporto",
        "Interface" => "SIP/201",
        "MemberName" => "Alice",
        "Paused" => "1")
      bridge.instance_variable_get(:@queue).push({type: :event, event: event})

      msg = bridge.next_event
      expect(msg).to be_a(Pbx::Messages::QueueMemberUpdated)
      expect(msg.status).to be_nil
      expect(msg.paused).to be true
    end

    it "translates QueueMemberRemoved to QueueMemberGone" do
      event = fake_client.inject_event("QueueMemberRemoved",
        "Queue" => "supporto",
        "Location" => "SIP/201")
      bridge.instance_variable_get(:@queue).push({type: :event, event: event})

      msg = bridge.next_event
      expect(msg).to be_a(Pbx::Messages::QueueMemberGone)
      expect(msg.queue).to eq("supporto")
      expect(msg.interface).to eq("SIP/201")
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

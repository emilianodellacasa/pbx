# frozen_string_literal: true

RSpec.describe Pbx::App do
  let(:config) do
    Pbx::Config::Value.new(
      host: "127.0.0.1", port: 5038, user: "admin", secret: "s3cret",
      context: "default", reconnect_backoff: [1]
    )
  end

  let(:fake_client) { FakeAmiClient.new }
  let(:bridge)      { Pbx::AmiBridge.new(config, client: fake_client) }
  subject(:app)     { described_class.new(bridge: bridge, config: config) }

  describe "#init" do
    it "returns [model, command]" do
      model, cmd = app.init
      expect(model).to be_a(described_class)
      expect(cmd).not_to be_nil
    end

    it "starts in :connecting status when config is complete" do
      expect(app.status).to eq(:connecting)
    end

    context "when config is incomplete (no credentials)" do
      let(:config) do
        Pbx::Config::Value.new(
          host: "127.0.0.1", port: 5038, user: nil, secret: nil,
          context: "default", reconnect_backoff: [1]
        )
      end

      it "starts in :disconnected status" do
        expect(app.status).to eq(:disconnected)
      end

      it "does not schedule connect_cmd (returns only tick command)" do
        _, cmd = app.init
        expect(cmd).to be_a(Bubbletea::TickCommand)
      end
    end
  end

  describe "info modal" do
    let(:key_i) { Bubbletea::KeyMessage.new(key_type: Bubbletea::KeyMessage::KEY_RUNES, runes: "i".unpack("U*")) }
    let(:any_key) { Bubbletea::KeyMessage.new(key_type: Bubbletea::KeyMessage::KEY_RUNES, runes: "x".unpack("U*")) }

    it "starts with modal closed" do
      expect(app.show_info).to be false
    end

    it "opens the modal on 'i'" do
      new_app, = app.update(key_i)
      expect(new_app.show_info).to be true
    end

    it "closes the modal on any key when open" do
      app.update(key_i)   # open
      new_app, = app.update(any_key)
      expect(new_app.show_info).to be false
    end

    it "does not quit when pressing any key while modal is open" do
      app.update(key_i)   # open
      quit_key = Bubbletea::KeyMessage.new(key_type: Bubbletea::KeyMessage::KEY_RUNES, runes: "q".unpack("U*"))
      app.instance_variable_set(:@show_info, true)
      _, cmd = app.update(quit_key)
      expect(cmd).not_to be_a(Bubbletea::QuitCommand)
    end

    it "renders info modal in view when open" do
      app.instance_variable_set(:@show_info, true)
      expect(app.view).to include("Emiliano Della Casa")
    end

    it "renders normal view when modal is closed" do
      expect(app.view).not_to include("Emiliano Della Casa")
    end
  end

  describe "#update" do
    context "with quit key q" do
      it "returns QuitCommand" do
        msg = Bubbletea::KeyMessage.new(key_type: Bubbletea::KeyMessage::KEY_RUNES, runes: "q".unpack("U*"))
        _, cmd = app.update(msg)
        expect(cmd).to be_a(Bubbletea::QuitCommand)
      end
    end

    context "with Esc key" do
      it "returns QuitCommand" do
        msg = Bubbletea::KeyMessage.new(key_type: Bubbletea::KeyMessage::KEY_ESC)
        _, cmd = app.update(msg)
        expect(cmd).to be_a(Bubbletea::QuitCommand)
      end
    end

    context "with WindowSizeMessage" do
      it "updates width and height" do
        msg = Bubbletea::WindowSizeMessage.new(width: 120, height: 40)
        new_app, = app.update(msg)
        expect(new_app.width).to eq(120)
        expect(new_app.height).to eq(40)
      end
    end

    context "with ConnectionEstablished" do
      let(:peers) do
        [
          Pbx::Peer.new(id: "alice", name: "alice", ip_address: "192.168.1.10",
                        ip_port: 5060, status: "registered", type: "friend",
                        dynamic: "yes", user_agent: nil, rtt_ms: nil, last_change_at: nil)
        ]
      end
      let(:msg) { Pbx::Messages::ConnectionEstablished.new(remote: "127.0.0.1:5038", peers: peers) }

      it "sets status to :connected" do
        new_app, = app.update(msg)
        expect(new_app.status).to eq(:connected)
      end

      it "loads peers into extensions keyed by name" do
        new_app, = app.update(msg)
        expect(new_app.extensions).to have_key("alice")
      end

      it "returns a wait_for_event Proc command" do
        _, cmd = app.update(msg)
        expect(cmd).to be_a(Proc)
      end
    end

    context "with ConnectionLost" do
      let(:msg) { Pbx::Messages::ConnectionLost.new(reason: "Connection reset") }

      it "sets status to :lost" do
        new_app, = app.update(msg)
        expect(new_app.status).to eq(:lost)
      end

      it "stores the error reason" do
        new_app, = app.update(msg)
        expect(new_app.error).to eq("Connection reset")
      end
    end

    context "with PeerStatusChanged" do
      before do
        peer = Pbx::Peer.new(id: "alice", name: "alice", ip_address: "192.168.1.10",
                             ip_port: 5060, status: "registered", type: "friend",
                             dynamic: "yes", user_agent: nil, rtt_ms: 5, last_change_at: nil)
        app.instance_variable_get(:@extensions)["alice"] = peer
        app.instance_variable_set(:@status, :connected)
      end

      let(:msg) do
        Pbx::Messages::PeerStatusChanged.new(
          peer_name: "alice", status: "unreachable", at: Time.now
        )
      end

      it "updates the peer status" do
        new_app, = app.update(msg)
        expect(new_app.extensions["alice"].status).to eq("unreachable")
      end

      it "preserves existing ip_address when not provided in message" do
        new_app, = app.update(msg)
        expect(new_app.extensions["alice"].ip_address).to eq("192.168.1.10")
      end

      it "returns a wait_for_event Proc command" do
        _, cmd = app.update(msg)
        expect(cmd).to be_a(Proc)
      end
    end

    context "with Tick" do
      let(:msg) { Pbx::Messages::Tick.new(at: Time.now) }

      it "returns a tick command" do
        _, cmd = app.update(msg)
        expect(cmd).to be_a(Bubbletea::TickCommand)
      end
    end

    context "with CallStarted" do
      let(:msg) do
        Pbx::Messages::CallStarted.new(
          uniqueid:    "1234567890.1",
          channel:     "SIP/alice-00000001",
          caller_id:   "101",
          caller_name: "Alice",
          state:       "Ring",
          started_at:  Time.now
        )
      end

      it "adds the call to active_calls" do
        new_app, = app.update(msg)
        expect(new_app.active_calls).to have_key("1234567890.1")
      end

      it "stores call details" do
        new_app, = app.update(msg)
        call = new_app.active_calls["1234567890.1"]
        expect(call.channel).to eq("SIP/alice-00000001")
        expect(call.caller_id).to eq("101")
        expect(call.state).to eq("Ring")
      end

      it "returns a wait_for_event Proc command" do
        _, cmd = app.update(msg)
        expect(cmd).to be_a(Proc)
      end
    end

    context "with CallEnded" do
      before do
        app.instance_variable_get(:@active_calls)["1234567890.1"] = Pbx::Call.new(
          uniqueid: "1234567890.1", channel: "SIP/alice-00000001",
          caller_id: "101", caller_name: "Alice",
          connected_to: nil, state: "Up", started_at: Time.now
        )
      end

      let(:msg) { Pbx::Messages::CallEnded.new(uniqueid: "1234567890.1") }

      it "removes the call from active_calls" do
        new_app, = app.update(msg)
        expect(new_app.active_calls).not_to have_key("1234567890.1")
      end

      it "returns a wait_for_event Proc command" do
        _, cmd = app.update(msg)
        expect(cmd).to be_a(Proc)
      end
    end

    context "with CallStateChanged" do
      before do
        app.instance_variable_get(:@active_calls)["1234567890.1"] = Pbx::Call.new(
          uniqueid: "1234567890.1", channel: "SIP/alice-00000001",
          caller_id: "101", caller_name: "Alice",
          connected_to: nil, state: "Ring", started_at: Time.now
        )
      end

      let(:msg) do
        Pbx::Messages::CallStateChanged.new(
          uniqueid:     "1234567890.1",
          state:        "Up",
          connected_to: "102"
        )
      end

      it "updates the call state" do
        new_app, = app.update(msg)
        expect(new_app.active_calls["1234567890.1"].state).to eq("Up")
      end

      it "updates connected_to" do
        new_app, = app.update(msg)
        expect(new_app.active_calls["1234567890.1"].connected_to).to eq("102")
      end

      it "preserves existing connected_to when not provided" do
        app.instance_variable_get(:@active_calls)["1234567890.1"] = Pbx::Call.new(
          uniqueid: "1234567890.1", channel: "SIP/alice-00000001",
          caller_id: "101", caller_name: "Alice",
          connected_to: "102", state: "Up", started_at: Time.now
        )
        msg_no_connected = Pbx::Messages::CallStateChanged.new(uniqueid: "1234567890.1", state: "Ringing")
        new_app, = app.update(msg_no_connected)
        expect(new_app.active_calls["1234567890.1"].connected_to).to eq("102")
      end

      it "returns a wait_for_event Proc command" do
        _, cmd = app.update(msg)
        expect(cmd).to be_a(Proc)
      end
    end
  end

  describe "#view" do
    it "returns a non-empty string" do
      expect(app.view).to be_a(String)
      expect(app.view).not_to be_empty
    end

    it "includes the host in the view" do
      expect(app.view).to include("127.0.0.1")
    end
  end
end

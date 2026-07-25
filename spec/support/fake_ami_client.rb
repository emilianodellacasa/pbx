# frozen_string_literal: true

# Duck-typed stand-in for RubyAsterisk::AMI::Client.
#
# Resolves promises synchronously and builds AMI events for specs to feed to the
# bridge. List actions mirror the real gem: their items are aggregated into the
# action's Response and never reach the event stream.
class FakeAmiClient
  FakePromise = Struct.new(:response) do
    def value(_timeout = 5) = response
  end

  FakeResponse = Struct.new(:success, :data, :message, :raw_response) do
    def success = self[:success]
  end

  attr_reader :connected, :logged_in

  def initialize(peers: [], queues: [], pjsip_endpoints: [])
    @peers = peers
    @queues = queues
    @pjsip_endpoints = pjsip_endpoints
    @connected = false
    @logged_in = false
  end

  def connect
    @connected = true
    true
  end

  def disconnect
    @connected = false
    true
  end

  def login(username:, secret:)
    @logged_in = true
    FakePromise.new(FakeResponse.new(true, {}, "Authentication accepted"))
  end

  def logoff
    FakePromise.new(FakeResponse.new(true, {}, nil))
  end

  def sip_peers
    list_promise(
      "Peer status list will follow",
      @peers.map { |peer_data| frame("PeerEntry", peer_data) },
      "PeerlistComplete", "ListItems" => @peers.size.to_s
    )
  end

  def queue_status
    item_frames = @queues.flat_map do |queue_data|
      queue_name = queue_data.fetch("Queue")
      members = queue_data["members"] || []
      [
        frame("QueueParams", queue_data.except("members")),
        *members.map { |m| frame("QueueMember", m.merge("Queue" => queue_name)) }
      ]
    end
    list_promise("Queue status will follow", item_frames, "QueueStatusComplete")
  end

  def pjsip_show_endpoints
    list_promise(
      "A listing of Endpoints follows",
      @pjsip_endpoints.map { |ep| frame("EndpointList", ep) },
      "EndpointListComplete"
    )
  end

  def event_mask(_mask)
    FakePromise.new(FakeResponse.new(true, {}, nil, ["Response: Success\r\nEvents: On\r\n\r\n"]))
  end

  def execute(_command, _options = {})
    FakePromise.new(FakeResponse.new(false, {}, "Unknown command"))
  end

  # Builds an unsolicited AMI event for a spec to push onto the bridge queue,
  # standing in for what EventClient#handle_event does against a live PBX.
  def inject_event(name, headers = {})
    all_headers = headers.merge("Event" => name)
    raw = all_headers.map { |k, v| "#{k}: #{v}" }.join("\r\n") + "\r\n\r\n"
    RubyAsterisk::AMI::Event.new(all_headers.transform_values(&:to_s), raw.freeze)
  end

  private

  # Mirrors how ruby-asterisk aggregates a list action's reply: the ack frame
  # opening the EventList, one Event frame per item, then the terminating
  # Complete event — all joined into the Response the promise resolves with.
  # List items deliberately never reach the event queue, exactly as in the gem.
  def list_promise(message, item_frames, complete_event, complete_headers = {})
    ack = "Response: Success\r\nEventList: start\r\nMessage: #{message}\r\n\r\n"
    complete = frame(complete_event, complete_headers.merge("EventList" => "Complete"))
    raw = [ack, *item_frames, complete].join
    FakePromise.new(FakeResponse.new(true, {}, message, [raw]))
  end

  def frame(event_name, headers)
    headers.transform_keys(&:to_s)
      .merge("Event" => event_name)
      .map { |k, v| "#{k}: #{v}" }.join("\r\n") + "\r\n\r\n"
  end
end

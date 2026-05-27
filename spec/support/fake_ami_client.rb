# frozen_string_literal: true

# Duck-typed stand-in for RubyAsterisk::AMI::Client.
# Resolves promises synchronously and allows injecting events.
class FakeAmiClient
  FakePromise = Struct.new(:response) do
    def value(_timeout = 5) = response
  end

  FakeResponse = Struct.new(:success, :data, :message) do
    def success = self[:success]
  end

  attr_reader :connected, :logged_in, :injected_events
  attr_writer :event_queue

  def initialize(peers: [], queues: [], pjsip_endpoints: [])
    @peers = peers
    @queues = queues
    @pjsip_endpoints = pjsip_endpoints
    @connected = false
    @logged_in = false
    @injected_events = []
    @event_queue = nil
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
    if @event_queue
      @peers.each { |peer_data| push_event("PeerEntry", peer_data) }
      push_event("PeerlistComplete", "ListItems" => @peers.size.to_s)
    end
    FakePromise.new(FakeResponse.new(true, {peers: []}, nil))
  end

  def queue_status
    if @event_queue
      @queues.each do |queue_data|
        queue_name = queue_data.fetch("Queue")
        members = queue_data.delete("members") || []
        push_event("QueueParams", queue_data)
        members.each { |m| push_event("QueueMember", m.merge("Queue" => queue_name)) }
      end
      push_event("QueueStatusComplete", "EventList" => "Complete")
    end
    FakePromise.new(FakeResponse.new(true, {}, nil))
  end

  def pjsip_show_endpoints
    if @event_queue
      @pjsip_endpoints.each { |ep| push_event("EndpointList", ep) }
      push_event("EndpointListComplete", "EventList" => "Complete")
    end
    FakePromise.new(FakeResponse.new(true, {}, nil))
  end

  def event_mask(_mask)
    FakePromise.new(FakeResponse.new(true, {}, nil))
  end

  def execute(_command, _options = {})
    FakePromise.new(FakeResponse.new(false, {}, "Unknown command"))
  end

  # Inject an AMI event into the client's event pipeline (simulates push events).
  def inject_event(name, headers = {})
    all_headers = headers.merge("Event" => name)
    raw = all_headers.map { |k, v| "#{k}: #{v}" }.join("\r\n") + "\r\n\r\n"
    event = RubyAsterisk::AMI::Event.new(all_headers.transform_values(&:to_s), raw.freeze)
    @injected_events << event
    event
  end

  private

  def push_event(name, headers = {})
    all_headers = headers.transform_keys(&:to_s).transform_values(&:to_s).merge("Event" => name)
    raw = all_headers.map { |k, v| "#{k}: #{v}" }.join("\r\n") + "\r\n\r\n"
    event = RubyAsterisk::AMI::Event.new(all_headers, raw.freeze)
    @event_queue.push({type: :event, event: event})
  end
end

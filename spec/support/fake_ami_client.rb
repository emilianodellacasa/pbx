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

  def initialize(peers: [])
    @peers           = peers
    @connected       = false
    @logged_in       = false
    @injected_events = []
    @event_queue     = nil
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
    FakePromise.new(FakeResponse.new(true, { peers: [] }, nil))
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
    raw         = all_headers.map { |k, v| "#{k}: #{v}" }.join("\r\n") + "\r\n\r\n"
    event       = RubyAsterisk::AMI::Event.new(all_headers.transform_values(&:to_s), raw.freeze)
    @injected_events << event
    event
  end

  private

  def push_event(name, headers = {})
    all_headers = headers.transform_keys(&:to_s).transform_values(&:to_s).merge("Event" => name)
    raw         = all_headers.map { |k, v| "#{k}: #{v}" }.join("\r\n") + "\r\n\r\n"
    event       = RubyAsterisk::AMI::Event.new(all_headers, raw.freeze)
    @event_queue.push({ type: :event, event: event })
  end
end

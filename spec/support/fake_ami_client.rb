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

  def initialize(peers: [], pjsip_endpoints: [])
    @peers            = peers
    @pjsip_endpoints  = pjsip_endpoints
    @connected        = false
    @logged_in        = false
    @event_handlers   = []
    @injected_events  = []
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
    FakePromise.new(FakeResponse.new(true, { peers: @peers }, nil))
  end

  def event_mask(_mask)
    FakePromise.new(FakeResponse.new(true, {}, nil))
  end

  def execute(command, _options = {})
    case command
    when "PJSIPShowEndpoints"
      raw = @pjsip_endpoints.map { |ep|
        "Event: EndpointList\nObjectName: #{ep[:name]}\nDeviceState: #{ep[:state] || "Not_InUse"}"
      }.join("\n\n")
      FakePromise.new(FakeResponse.new(true, {}, nil).tap { |r|
        r.define_singleton_method(:raw_response) { [raw] }
      })
    else
      FakePromise.new(FakeResponse.new(false, {}, "Unknown command"))
    end
  end

  # Inject an AMI event into the client's event pipeline (simulates push events).
  def inject_event(name, headers = {})
    all_headers = headers.merge("Event" => name)
    raw         = all_headers.map { |k, v| "#{k}: #{v}" }.join("\r\n") + "\r\n\r\n"
    event       = RubyAsterisk::AMI::Event.new(all_headers.transform_values(&:to_s), raw.freeze)
    @injected_events << event
    event
  end
end

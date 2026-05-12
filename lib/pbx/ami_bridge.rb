# frozen_string_literal: true

require "ruby-asterisk"
require_relative "peer"
require_relative "messages"
require_relative "status"

module Pbx
  class AmiBridge
    SENTINEL = :__pbx_shutdown__

    # Subclass that routes parsed AMI events into a Ruby Queue,
    # enabling the Bubbletea command loop to consume them.
    class EventClient < RubyAsterisk::AMI::Client
      def initialize(host:, port:, queue:)
        super(host: host, port: port)
        @event_queue = queue
      end

      private

      def dispatch_message(msg)
        super
        @event_queue.push(msg) if msg[:type] == :event
      end
    end

    def initialize(config, client: nil)
      @config = config
      @queue  = Queue.new
      @client = client || EventClient.new(
        host:  config.host,
        port:  config.port,
        queue: @queue
      )
    end

    def connect_and_login
      unless @client.connect
        raise "Could not connect to #{@config.host}:#{@config.port}"
      end

      response = @client.login(username: @config.user, secret: @config.secret).value(5)
      raise "AMI login failed: #{response&.message}" unless response&.success
    end

    def discover_peers
      peers = []
      peers += sip_peers
      peers += pjsip_endpoints
      peers
    end

    def subscribe
      # Events are already flowing into @queue via EventClient#dispatch_message.
      # Request all event types from Asterisk.
      @client.event_mask("all")
    end

    def next_event(timeout: nil)
      loop do
        raw = timeout ? @queue.pop : @queue.pop
        return nil if raw == SENTINEL

        msg = translate_event(raw[:event])
        return msg if msg
      end
    end

    def shutdown
      @queue.push(SENTINEL)
      @client.logoff rescue nil
      @client.disconnect rescue nil
    end

    private

    def sip_peers
      response = @client.sip_peers.value(5)
      return [] unless response&.success

      (response.data[:peers] || []).map { |p| peer_from_sip(p) }.compact
    rescue => e
      warn "SIP peer discovery failed: #{e.message}"
      []
    end

    def pjsip_endpoints
      response = @client.execute("PJSIPShowEndpoints").value(5)
      return [] unless response

      raw = [response.raw_response].flatten.join
      endpoints = []
      raw.scan(/Event: EndpointList\n(.*?)\n\n/m) do |match|
        headers = parse_headers(match[0])
        next unless headers["ObjectName"]

        endpoints << Peer.new(
          id:             "PJSIP/#{headers["ObjectName"]}",
          extension:      headers["ObjectName"],
          context:        @config.context,
          label:          headers["DeviceState"] || headers["ObjectName"],
          status_code:    device_state_to_code(headers["DeviceState"]),
          last_change_at: nil
        )
      end
      endpoints
    rescue => e
      warn "PJSIP endpoint discovery failed: #{e.message}"
      []
    end

    def peer_from_sip(data)
      return nil unless data["ObjectName"]

      Peer.new(
        id:             "SIP/#{data["ObjectName"]}",
        extension:      data["ObjectName"],
        context:        @config.context,
        label:          data["Description"] || data["ObjectName"],
        status_code:    sip_status_to_code(data["Status"]),
        last_change_at: nil
      )
    end

    def translate_event(event)
      return nil unless event.is_a?(RubyAsterisk::AMI::Event)

      case event.name
      when "ExtensionStatus", "DeviceStateChange"
        peer_id    = event.headers["Exten"] || event.headers["Device"]
        status_str = event.headers["StatusText"] || event.headers["State"] || ""
        Messages::LineStatusChanged.new(
          peer_id:     peer_id,
          status_code: text_to_code(status_str),
          at:          Time.now
        )
      when "PeerStatus"
        peer_id = event.headers["Peer"]
        status  = event.headers["PeerStatus"] == "Registered" ? "0" : "3"
        Messages::LineStatusChanged.new(
          peer_id:     peer_id,
          status_code: status,
          at:          Time.now
        )
      when "Newchannel"
        # A new channel on an extension — mark as in-use
        exten = event.headers["Exten"]
        return nil if exten.nil? || exten == "s"

        Messages::LineStatusChanged.new(
          peer_id:     exten,
          status_code: "1",
          at:          Time.now
        )
      when "Hangup"
        # Channel hung up — mark as idle
        exten = event.headers["Exten"]
        return nil if exten.nil? || exten == "s"

        Messages::LineStatusChanged.new(
          peer_id:     exten,
          status_code: "0",
          at:          Time.now
        )
      end
    end

    def sip_status_to_code(status_str)
      return "3" if status_str.nil?

      case status_str.downcase
      when /ok/           then "0"
      when /lagged/       then "0"
      when /unreachable/  then "3"
      when /unmonitored/  then "3"
      else                     "3"
      end
    end

    def device_state_to_code(state)
      return "3" if state.nil?

      case state.downcase
      when "not_inuse"  then "0"
      when "inuse"      then "1"
      when "busy"       then "2"
      when "ringing"    then "4"
      when "onhold"     then "5"
      else                   "3"
      end
    end

    def text_to_code(text)
      return "3" if text.nil?

      case text.downcase
      when /idle/        then "0"
      when /inuse/, /in use/ then "1"
      when /busy/        then "2"
      when /unavail/     then "3"
      when /ringing/     then "4"
      when /hold/        then "5"
      else                    "3"
      end
    end

    def parse_headers(raw)
      raw.split("\n").each_with_object({}) do |line, h|
        k, v = line.split(":", 2)
        h[k.strip] = v&.strip
      end
    end
  end
end

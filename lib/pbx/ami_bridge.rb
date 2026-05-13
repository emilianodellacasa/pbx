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
      def initialize(host:, port:, queue:, log: nil)
        super(host: host, port: port)
        @event_queue = queue
        @log = log
      end

      private

      def dispatch_message(msg)
        super
        if @log
          @log.puts "[DISPATCH] type=#{msg[:type]} event=#{msg[:event]&.headers&.inspect}"
          @log.flush
        end
        @event_queue.push(msg) if msg[:type] == :event
      end
    end

    def initialize(config, client: nil, debug: false)
      @config    = config
      @queue     = Queue.new
      @debug_log = debug ? File.open("/tmp/pbx_debug.log", "a") : nil
      @client    = client || EventClient.new(
        host:  config.host,
        port:  config.port,
        queue: @queue,
        log:   @debug_log
      )
      # Allow test doubles to receive events via the same queue
      @client.event_queue = @queue if @client.respond_to?(:event_queue=)
    end

    def connect_and_login
      log "[CONNECT] Connecting to #{@config.host}:#{@config.port} as #{@config.user}"
      raise "Could not connect to #{@config.host}:#{@config.port}" unless @client.connect

      response = @client.login(username: @config.user, secret: @config.secret).value(5)
      log "[CONNECT] Login response: success=#{response&.success} message=#{response&.message}"
      raise "AMI login failed: #{response&.message}" unless response&.success
    end

    def discover_peers
      # Trigger the SIPPeers AMI action; Asterisk responds with a flood of
      # PeerEntry events (not inline in the response payload) followed by
      # PeerlistComplete to signal the end of the list.
      log "[DISCOVER] Triggering sip_peers action..."
      @client.sip_peers

      peers            = []
      non_peer_events  = []

      loop do
        raw = @queue.pop
        return [] if raw == SENTINEL

        next unless raw[:type] == :event

        event = raw[:event]
        next unless event.is_a?(RubyAsterisk::AMI::Event)

        case event.name
        when "PeerEntry"
          log "[DISCOVER] PeerEntry: #{event.headers["ObjectName"]} status=#{event.headers["Status"]}"
          peer = peer_from_sip(event.headers)
          peers << peer if peer
        when "PeerlistComplete"
          log "[DISCOVER] PeerlistComplete — collected #{peers.size} peers"
          break
        else
          non_peer_events << raw
        end
      end

      non_peer_events.each { |e| @queue.push(e) }
      log "[DISCOVER] Returning #{peers.size} peers: #{peers.map(&:name).inspect}"
      peers
    rescue => e
      log "[DISCOVER] Error: #{e.class}: #{e.message}\n#{e.backtrace&.first(3)&.join("\n")}"
      warn "SIP peer discovery failed: #{e.message}"
      []
    end

    def subscribe
      @client.event_mask("all")
    end

    def next_event
      loop do
        raw = @queue.pop
        return nil if raw == SENTINEL

        msg = translate_event(raw[:event])
        return msg if msg
      end
    end

    def shutdown
      @queue.push(SENTINEL)
      @client.logoff rescue nil
      @client.disconnect rescue nil
      @debug_log&.close
    end

    private

    def log(msg)
      return unless @debug_log

      @debug_log.puts "[#{Time.now.strftime("%H:%M:%S")}] #{msg}"
      @debug_log.flush
    rescue IOError
      nil
    end

    def peer_from_sip(data)
      return nil unless data["ObjectName"]

      name       = data["ObjectName"]
      raw_status = data["Status"].to_s
      ip_raw     = data["IPaddress"].to_s
      ip_address = ip_raw.empty? || ip_raw == "-none-" ? nil : ip_raw
      ip_port    = data["IPport"].to_s.then { |p| p.empty? || p == "0" ? nil : p.to_i }

      Peer.new(
        id:             name,
        name:           name,
        ip_address:     ip_address,
        ip_port:        ip_port,
        status:         Status.from_sip(raw_status),
        type:           data["Type"],
        dynamic:        data["Dynamic"],
        user_agent:     data["SIP-Useragent"],
        rtt_ms:         Status.rtt_from_sip(raw_status),
        last_change_at: nil
      )
    end

    def translate_event(event)
      log "[EVENT] class=#{event.class}"
      return nil unless event.is_a?(RubyAsterisk::AMI::Event)

      log "[EVENT] name=#{event.name} headers=#{event.headers.inspect}"
      return nil unless event.name == "PeerStatus"
      return nil unless event.headers["ChannelType"]&.upcase == "SIP"

      raw_peer = event.headers["Peer"].to_s
      name     = raw_peer.sub(/\ASIP\//i, "")
      return nil if name.empty?

      peer_status = event.headers["PeerStatus"].to_s
      address     = event.headers["Address"].to_s
      ip_address, ip_port = parse_address(address)
      rtt_ms = event.headers["Time"].to_s.then { |t| t.empty? ? nil : t.to_i }

      Messages::PeerStatusChanged.new(
        peer_name:  name,
        status:     Status.from_sip(peer_status),
        ip_address: ip_address,
        ip_port:    ip_port,
        rtt_ms:     rtt_ms,
        at:         Time.now
      )
    end

    def parse_address(address)
      return [nil, nil] if address.nil? || address.empty?

      parts = address.split(":")
      ip   = parts[0].then { |h| h.empty? ? nil : h }
      port = parts[1].to_s.then { |p| p.empty? ? nil : p.to_i }
      [ip, port]
    end
  end
end

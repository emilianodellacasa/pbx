# frozen_string_literal: true

require "ruby-asterisk"
require_relative "peer"
require_relative "call_queue"
require_relative "queue_member"
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

      def pjsip_show_endpoints
        execute "PJSIPShowEndpoints", {}
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
      @config = config
      @queue = Queue.new
      @debug_log = debug ? File.open("/tmp/pbx_debug.log", "a") : nil
      @client = client || EventClient.new(
        host: config.host,
        port: config.port,
        queue: @queue,
        log: @debug_log
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
      discover_sip_peers + discover_pjsip_endpoints
    end

    def discover_queues
      log "[QUEUES] Triggering queue_status action..."
      @client.queue_status

      queues = {}
      non_queue_events = []

      loop do
        raw = @queue.pop
        return {} if raw == SENTINEL

        next unless raw[:type] == :event

        event = raw[:event]
        next unless event.is_a?(RubyAsterisk::AMI::Event)

        case event.name
        when "QueueParams"
          q = queue_from_params(event.headers)
          queues[q.name] = q if q
        when "QueueMember"
          queue_name = event.headers["Queue"].to_s
          next if queue_name.empty? || !queues[queue_name]

          member = member_from_event(event.headers)
          if member
            existing = queues[queue_name]
            queues[queue_name] = existing.with(members: existing.members.merge(member.interface => member))
          end
        when "QueueEntry"
          # caller count is already in QueueParams Calls header; skip
        when "QueueStatusComplete"
          log "[QUEUES] QueueStatusComplete — collected #{queues.size} queues"
          break
        else
          # Same re-queue trade-off as discover_sip_peers: events are appended
          # to the tail of the queue, losing chronological order with respect to
          # events that arrived in the meantime.
          non_queue_events << raw
        end
      end

      non_queue_events.each { |e| @queue.push(e) }
      log "[QUEUES] Returning #{queues.size} queues: #{queues.keys.inspect}"
      queues
    rescue => e
      log "[QUEUES] Error: #{e.class}: #{e.message}\n#{e.backtrace&.first(3)&.join("\n")}"
      warn "Queue discovery failed: #{e.message}"
      {}
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
      begin
        @client.logoff
      rescue
        nil
      end
      begin
        @client.disconnect
      rescue
        nil
      end
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

    def discover_sip_peers
      log "[DISCOVER] Triggering sip_peers action..."
      @client.sip_peers

      peers = []
      non_peer_events = []

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
          # Non-SIP events that arrived during discovery are buffered and
          # re-pushed after the loop. This preserves no chronological order
          # guarantee but is safe at startup where ordering rarely matters.
          non_peer_events << raw
        end
      end

      non_peer_events.each { |e| @queue.push(e) }
      peers
    rescue => e
      log "[DISCOVER] Error: #{e.class}: #{e.message}\n#{e.backtrace&.first(3)&.join("\n")}"
      warn "SIP peer discovery failed: #{e.message}"
      []
    end

    def discover_pjsip_endpoints
      log "[PJSIP] Triggering PJSIPShowEndpoints action..."
      @client.pjsip_show_endpoints

      peers = []
      non_ep_events = []

      loop do
        raw = @queue.pop
        return [] if raw == SENTINEL

        next unless raw[:type] == :event

        event = raw[:event]
        next unless event.is_a?(RubyAsterisk::AMI::Event)

        case event.name
        when "EndpointList"
          peer = peer_from_pjsip(event.headers)
          peers << peer if peer
        when "EndpointListComplete"
          log "[PJSIP] EndpointListComplete — collected #{peers.size} PJSIP endpoints"
          break
        else
          non_ep_events << raw
        end
      end

      non_ep_events.each { |e| @queue.push(e) }
      peers
    rescue => e
      log "[PJSIP] Error: #{e.class}: #{e.message}"
      []
    end

    def queue_from_params(data)
      name = data["Queue"].to_s
      return nil if name.empty?

      CallQueue.new(
        name: name,
        strategy: data["Strategy"].to_s,
        calls_waiting: data["Calls"].to_i,
        completed: data["Completed"].to_i,
        abandoned: data["Abandoned"].to_i,
        holdtime: data["Holdtime"].to_i,
        members: {}
      )
    end

    def member_from_event(data)
      interface = data["Location"].to_s
      interface = data["Interface"].to_s if interface.empty?
      return nil if interface.empty?

      QueueMember.new(
        queue: data["Queue"].to_s,
        name: data["Name"].to_s,
        interface: interface,
        status: Status.queue_member_state(data["Status"].to_s),
        paused: data["Paused"].to_s == "1"
      )
    end

    def peer_from_sip(data)
      return nil unless data["ObjectName"]

      name = data["ObjectName"]
      raw_status = data["Status"].to_s
      ip_raw = data["IPaddress"].to_s
      ip_address = (ip_raw.empty? || ip_raw == "-none-") ? nil : ip_raw
      ip_port = data["IPport"].to_s.then { |p| (p.empty? || p == "0") ? nil : p.to_i }

      Peer.new(
        id: name,
        name: name,
        ip_address: ip_address,
        ip_port: ip_port,
        status: Status.from_sip(raw_status),
        type: data["Type"],
        dynamic: data["Dynamic"],
        user_agent: data["SIP-Useragent"],
        rtt_ms: Status.rtt_from_sip(raw_status),
        last_change_at: nil
      )
    end

    def peer_from_pjsip(data)
      name = data["ObjectName"].to_s
      return nil if name.empty?

      Peer.new(
        id: name,
        name: name,
        ip_address: nil,
        ip_port: nil,
        status: Status.from_pjsip_device_state(data["DeviceState"].to_s),
        type: "PJSIP",
        dynamic: nil,
        user_agent: nil,
        rtt_ms: nil,
        last_change_at: nil
      )
    end

    DIALPLAN_NOISE_APPS = %w[
      NoOp Verbose Set GotoIf GotoIfTime Goto Return ExecIf Wait
      Answer Progress Ringing ResetCDR NoCDR UserEvent Log Macro MacroExit
    ].freeze

    def translate_event(event)
      log "[EVENT] class=#{event.class}"
      return nil unless event.is_a?(RubyAsterisk::AMI::Event)

      log "[EVENT] name=#{event.name} headers=#{event.headers.inspect}"

      h = event.headers

      case event.name
      when "FullyBooted"
        Messages::SystemInfo.new(
          uptime_secs: h["Uptime"].to_i,
          last_reload_secs: h["LastReload"].to_i,
          received_at: Time.now
        )

      when "Newchannel"
        return nil unless h["Channel"].to_s.match?(/\A(SIP|PJSIP)\//i)

        Messages::CallStarted.new(
          uniqueid: h["Uniqueid"],
          channel: h["Channel"],
          caller_id: h["CallerIDNum"].to_s,
          caller_name: h["CallerIDName"].to_s,
          state: h["ChannelStateDesc"].to_s,
          started_at: Time.now
        )

      when "Hangup"
        return nil unless h["Channel"].to_s.match?(/\A(SIP|PJSIP)\//i)

        Messages::CallEnded.new(uniqueid: h["Uniqueid"])

      when "DialBegin"
        connected = h["DestCallerIDNum"].to_s
        connected = nil if connected.empty? || connected == "<unknown>"
        Messages::CallStateChanged.new(
          uniqueid: h["Uniqueid"],
          state: "Dialing",
          connected_to: connected
        )

      when "ChannelStateChange"
        return nil unless h["Channel"].to_s.match?(/\A(SIP|PJSIP)\//i)

        connected = h["ConnectedLineNum"].to_s
        connected = nil if connected.empty? || connected == "<unknown>"
        Messages::CallStateChanged.new(
          uniqueid: h["Uniqueid"],
          state: h["ChannelStateDesc"].to_s,
          connected_to: connected
        )

      when "DialEnd"
        Messages::DialCompleted.new(
          uniqueid: h["Uniqueid"].to_s,
          dial_status: h["DialStatus"].to_s
        )

      when "Hold", "MusicOnHoldStart"
        uniqueid = h["Uniqueid"].to_s
        return nil if uniqueid.empty?
        Messages::CallHeld.new(uniqueid: uniqueid)

      when "Unhold", "MusicOnHoldStop"
        uniqueid = h["Uniqueid"].to_s
        return nil if uniqueid.empty?
        Messages::CallUnheld.new(uniqueid: uniqueid)

      when "Newexten"
        uniqueid = h["Uniqueid"].to_s
        app = h["Application"].to_s
        return nil if uniqueid.empty? || app.empty?
        return nil if DIALPLAN_NOISE_APPS.include?(app)
        Messages::CallDialplanUpdate.new(
          uniqueid: uniqueid,
          context: h["Context"].to_s,
          exten: h["Extension"].to_s,
          application: app
        )

      when "QueueCallerJoin", "QueueCallerLeave"
        queue = h["Queue"].to_s
        return nil if queue.empty?

        Messages::QueueCallerCountChanged.new(
          queue: queue,
          count: h["Count"].to_i
        )

      when "QueueCallerAbandon"
        queue = h["Queue"].to_s
        return nil if queue.empty?

        Messages::QueueCallerAbandoned.new(queue: queue)

      when "QueueMemberStatus", "QueueMemberAdded"
        queue = h["Queue"].to_s
        interface = h["Location"].to_s
        interface = h["Interface"].to_s if interface.empty?
        return nil if queue.empty? || interface.empty?

        Messages::QueueMemberUpdated.new(
          queue: queue,
          interface: interface,
          name: h["Name"].to_s,
          status: Status.queue_member_state(h["Status"].to_s),
          paused: h["Paused"].to_s == "1"
        )

      when "QueueMemberPause"
        queue = h["Queue"].to_s
        interface = h["Location"].to_s
        interface = h["Interface"].to_s if interface.empty?
        return nil if queue.empty? || interface.empty?

        Messages::QueueMemberUpdated.new(
          queue: queue,
          interface: interface,
          name: h["MemberName"].to_s,
          status: nil,
          paused: h["Paused"].to_s == "1"
        )

      when "QueueMemberRemoved"
        queue = h["Queue"].to_s
        interface = h["Location"].to_s
        interface = h["Interface"].to_s if interface.empty?
        return nil if queue.empty? || interface.empty?

        Messages::QueueMemberGone.new(queue: queue, interface: interface)

      when "PeerStatus"
        channel_type = h["ChannelType"].to_s.upcase
        return nil unless %w[SIP PJSIP].include?(channel_type)

        name = h["Peer"].to_s.sub(/\A(SIP|PJSIP)\//i, "")
        return nil if name.empty?

        address = h["Address"].to_s
        ip_address, ip_port = parse_address(address)
        rtt_ms = h["Time"].to_s.then { |t| t.empty? ? nil : t.to_i }

        Messages::PeerStatusChanged.new(
          peer_name: name,
          status: Status.from_sip(h["PeerStatus"].to_s),
          ip_address: ip_address,
          ip_port: ip_port,
          rtt_ms: rtt_ms,
          at: Time.now
        )

      end
    end

    def parse_address(address)
      return [nil, nil] if address.nil? || address.empty?

      parts = address.split(":")
      ip = parts[0].then { |h| h.empty? ? nil : h }
      port = parts[1].to_s.then { |p| p.empty? ? nil : p.to_i }
      [ip, port]
    end
  end
end

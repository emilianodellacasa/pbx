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

    # Seconds to wait for a list action's aggregated reply. Longer than the
    # gem's 5s default: on a busy PBX a full peer or queue listing is slow.
    LIST_TIMEOUT = 10

    # AMI frames are CRLF-delimited on the wire; tolerate bare LF too.
    FRAME_DELIMITER = /\r?\n\r?\n/

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

      # Hook invoked by the reactor for every unsolicited AMI event. Events that
      # belong to a list action's reply never arrive here: the gem buffers them
      # by ActionID and aggregates them into that action's Response instead.
      def handle_event(event)
        super
        if @log
          @log.puts "[DISPATCH] event=#{event.headers.inspect}"
          @log.flush
        end
        @event_queue.push({type: :event, event: event})
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
      # QueueEntry frames are ignored: the caller count is already in the
      # QueueParams Calls header.
      entries = list_entries(@client.queue_status, "QueueParams", "QueueMember")

      queues = {}
      entries.each do |data|
        case data["Event"]
        when "QueueParams"
          q = queue_from_params(data)
          queues[q.name] = q if q
        when "QueueMember"
          queue_name = data["Queue"].to_s
          next if queue_name.empty? || !queues[queue_name]

          member = member_from_event(data)
          next unless member

          existing = queues[queue_name]
          queues[queue_name] = existing.with(members: existing.members.merge(member.interface => member))
        end
      end

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
      entries = list_entries(@client.sip_peers, "PeerEntry")
      log "[DISCOVER] collected #{entries.size} peer entries"
      entries.filter_map { |data| peer_from_sip(data) }
    rescue => e
      log "[DISCOVER] Error: #{e.class}: #{e.message}\n#{e.backtrace&.first(3)&.join("\n")}"
      warn "SIP peer discovery failed: #{e.message}"
      []
    end

    def discover_pjsip_endpoints
      log "[PJSIP] Triggering PJSIPShowEndpoints action..."
      entries = list_entries(@client.pjsip_show_endpoints, "EndpointList")
      log "[PJSIP] collected #{entries.size} PJSIP endpoints"
      entries.filter_map { |data| peer_from_pjsip(data) }
    rescue => e
      log "[PJSIP] Error: #{e.class}: #{e.message}"
      []
    end

    # AMI list actions reply with an ack frame, one Event frame per item and a
    # terminating Complete event. ruby-asterisk buffers that frame set by
    # ActionID and resolves the action's promise with the whole thing, so list
    # entries are read back from the Response rather than the event stream.
    #
    # Returns the header hash of every frame whose Event matches +event_names+,
    # in arrival order. An action that fails (e.g. SIPpeers with chan_sip
    # unloaded) resolves with a plain error frame and yields no entries.
    def list_entries(promise, *event_names)
      raw = promise&.value(LIST_TIMEOUT)&.raw_response
      return [] if raw.nil?

      raw.join.split(FRAME_DELIMITER).filter_map do |frame|
        headers = RubyAsterisk::AMI::Parser.parse_headers(frame)
        headers if event_names.include?(headers["Event"])
      end
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
        name: member_name_from(data),
        interface: interface,
        status: Status.queue_member_state(data["Status"].to_s),
        paused: data["Paused"].to_s == "1"
      )
    end

    def member_name_from(h)
      name = h["MemberName"].to_s
      name.empty? ? h["Name"].to_s : name
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
          name: member_name_from(h),
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
          name: member_name_from(h),
          status: nil,
          paused: h["Paused"].to_s == "1"
        )

      when "AgentComplete"
        queue = h["Queue"].to_s
        return nil if queue.empty?

        Messages::QueueCallCompleted.new(
          queue: queue,
          holdtime: h["HoldTime"].to_i
        )

      when "ContactStatus"
        aor = h["AOR"].to_s
        return nil if aor.empty?

        status_raw = h["ContactStatus"].to_s
        return nil if status_raw.empty?

        rtt_usec = h["RoundtripUsec"].to_s.then { |t| t.empty? ? nil : (t.to_f / 1000).round }

        Messages::PeerStatusChanged.new(
          peer_name: aor,
          status: Status.from_sip(status_raw),
          ip_address: nil,
          ip_port: nil,
          rtt_ms: rtt_usec,
          at: Time.now
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

# frozen_string_literal: true

require "bubbletea"
require "bubbles"
require "lipgloss"
require_relative "messages"
require_relative "views/header"
require_relative "views/extension_table"
require_relative "views/active_calls"
require_relative "views/queue_table"
require_relative "views/footer"
require_relative "views/disconnected_screen"
require_relative "views/info_modal"

module Pbx
  class App
    include Bubbletea::Model

    TICK_INTERVAL = 1  # seconds between "time since last change" refresh

    attr_reader :extensions, :active_calls, :queues, :status, :error, :width, :height, :config,
      :show_info, :system_boot_at, :last_reload_at, :view_mode

    def spinner_view = @spinner.view

    def initialize(bridge:, config:)
      @bridge = bridge
      @config = config
      @extensions = {}
      @active_calls = {}
      @queues = {}
      @status = @config.complete? ? :connecting : :disconnected
      @error = nil
      @width = 80
      @height = 24
      @table = nil
      @calls_table = nil
      @queues_table = nil
      @show_info = false
      @view_mode = :peers
      @spinner = Bubbles::Spinner.new(spinner: Bubbles::Spinners::DOT)
      @system_boot_at = nil
      @last_reload_at = nil
    end

    def init
      if @config.complete?
        @spinner, spinner_cmd = @spinner.init
        [self, Bubbletea.batch(connect_cmd, tick_cmd, spinner_cmd)]
      else
        [self, tick_cmd]
      end
    end

    def update(message)
      case message
      when Bubbletea::KeyMessage
        if @show_info
          @show_info = false
          return [self, nil]
        end

        return [self, Bubbletea.quit] if quit_key?(message)

        if message.runes? && message.char == "i"
          @show_info = true
          return [self, nil]
        end

        if message.runes? && message.char == "p" && @status == :connected
          @view_mode = :peers
          rebuild_table
          return [self, nil]
        end

        if message.runes? && message.char == "c" && @status == :connected
          @view_mode = :calls
          rebuild_table
          return [self, nil]
        end

        if message.runes? && message.char == "q" && @status == :connected
          @view_mode = :queues
          return [self, nil]
        end

        active_table = case @view_mode
        when :calls then @calls_table
        when :queues then @queues_table
        else @table
        end
        if active_table && @status == :connected
          updated, table_cmd = active_table.update(message)
          case @view_mode
          when :calls then @calls_table = updated
          when :queues then @queues_table = updated
          else @table = updated
          end
          return [self, table_cmd]
        end

      when Bubbletea::WindowSizeMessage
        @width = message.width
        @height = message.height
        if @status == :connected
          rebuild_table
          rebuild_calls_table
          rebuild_queues_table
        end

      when Messages::ConnectionEstablished
        @status = :connected
        @error = nil
        message.peers.each { |p| @extensions[p.id] = p }
        @queues = message.queues
        rebuild_table
        rebuild_queues_table
        return [self, wait_for_event_cmd]

      when Messages::ConnectionLost
        @status = :lost
        @error = message.reason
        return [self, wait_for_event_cmd]

      when Messages::PeerDiscovered
        @extensions[message.peer.id] = message.peer
        rebuild_table
        return [self, wait_for_event_cmd]

      when Messages::PeerStatusChanged
        if (peer = @extensions[message.peer_name])
          @extensions[peer.id] = Peer.new(
            id: peer.id,
            name: peer.name,
            ip_address: message.ip_address || peer.ip_address,
            ip_port: message.ip_port || peer.ip_port,
            status: message.status,
            type: peer.type,
            dynamic: peer.dynamic,
            user_agent: peer.user_agent,
            rtt_ms: message.rtt_ms || peer.rtt_ms,
            last_change_at: message.at
          )
          rebuild_table
        end
        return [self, wait_for_event_cmd]

      when Messages::CallStarted
        @active_calls[message.uniqueid] = Call.new(
          uniqueid: message.uniqueid,
          channel: message.channel,
          caller_id: message.caller_id,
          caller_name: message.caller_name,
          connected_to: nil,
          state: message.state,
          started_at: message.started_at,
          outcome: nil,
          held: false,
          dialplan_app: nil,
          dialplan_exten: nil
        )
        rebuild_table
        rebuild_calls_table
        return [self, wait_for_event_cmd]

      when Messages::CallEnded
        @active_calls.delete(message.uniqueid)
        rebuild_table
        rebuild_calls_table
        return [self, wait_for_event_cmd]

      when Messages::CallStateChanged
        if (call = @active_calls[message.uniqueid])
          @active_calls[call.uniqueid] = call.with(
            connected_to: message.connected_to || call.connected_to,
            state: message.state
          )
          rebuild_table
          rebuild_calls_table
        end
        return [self, wait_for_event_cmd]

      when Messages::DialCompleted
        if (call = @active_calls[message.uniqueid])
          @active_calls[call.uniqueid] = call.with(outcome: message.dial_status)
          rebuild_table
          rebuild_calls_table
        end
        return [self, wait_for_event_cmd]

      when Messages::CallHeld
        if (call = @active_calls[message.uniqueid])
          @active_calls[call.uniqueid] = call.with(held: true)
          rebuild_table
          rebuild_calls_table
        end
        return [self, wait_for_event_cmd]

      when Messages::CallUnheld
        if (call = @active_calls[message.uniqueid])
          @active_calls[call.uniqueid] = call.with(held: false)
          rebuild_table
          rebuild_calls_table
        end
        return [self, wait_for_event_cmd]

      when Messages::CallDialplanUpdate
        if (call = @active_calls[message.uniqueid])
          @active_calls[call.uniqueid] = call.with(
            dialplan_app: message.application,
            dialplan_exten: message.exten
          )
          rebuild_table
          rebuild_calls_table
        end
        return [self, wait_for_event_cmd]

      when Messages::QueueCallCompleted
        if (q = @queues[message.queue])
          @queues[message.queue] = q.with(
            completed: q.completed + 1,
            last_holdtime: message.holdtime
          )
          rebuild_queues_table
        end
        return [self, wait_for_event_cmd]

      when Messages::QueueCallerCountChanged
        if (q = @queues[message.queue])
          @queues[message.queue] = q.with(calls_waiting: message.count)
          rebuild_queues_table
        end
        return [self, wait_for_event_cmd]

      when Messages::QueueCallerAbandoned
        if (q = @queues[message.queue])
          @queues[message.queue] = q.with(abandoned: q.abandoned + 1)
          rebuild_queues_table
        end
        return [self, wait_for_event_cmd]

      when Messages::QueueMemberUpdated
        q = @queues[message.queue] || CallQueue.new(
          name: message.queue, strategy: "unknown", calls_waiting: 0,
          completed: 0, abandoned: 0, holdtime: 0, members: {}
        )
        existing = q.members[message.interface]
        updated_member = if existing
          existing.with(
            name: message.name.empty? ? existing.name : message.name,
            status: message.status || existing.status,
            paused: message.paused
          )
        else
          QueueMember.new(
            queue: message.queue,
            name: message.name,
            interface: message.interface,
            status: message.status || "unknown",
            paused: message.paused
          )
        end
        @queues[message.queue] = q.with(members: q.members.merge(message.interface => updated_member))
        rebuild_queues_table
        return [self, wait_for_event_cmd]

      when Messages::QueueMemberGone
        if (q = @queues[message.queue])
          @queues[message.queue] = q.with(members: q.members.reject { |k, _| k == message.interface })
          rebuild_queues_table
        end
        return [self, wait_for_event_cmd]

      when Messages::SystemInfo
        @system_boot_at = message.received_at - message.uptime_secs
        @last_reload_at = message.received_at - message.last_reload_secs
        return [self, wait_for_event_cmd]

      when Messages::AmiError
        @error = message.error.to_s
        return [self, wait_for_event_cmd]

      when Messages::Tick
        rebuild_table if @status == :connected && !@extensions.empty?
        return [self, tick_cmd]

      end

      @spinner, spinner_cmd = @spinner.update(message)
      [self, spinner_cmd]
    end

    def view
      return Views::InfoModal.call(self) if @show_info

      header = Views::Header.call(self)
      body = build_body
      footer = Views::Footer.call(self)
      content = Lipgloss.join_vertical(:left, header, body, footer)
      Lipgloss.place(@width, @height, :left, :top, content)
    end

    private

    def build_body
      case @status
      when :disconnected
        Views::DisconnectedScreen.call(self)
      when :connecting
        ""
      else
        if @view_mode == :calls
          height = [[@active_calls.size, @height - 8].min, 1].max
          Views::ActiveCalls.render(@active_calls, @width, height, table: @calls_table)
        elsif @view_mode == :queues
          height = [[@queues.size, @height - 8].min, 1].max
          Views::QueueTable.render(@queues, @width, height, table: @queues_table)
        else
          @extensions.empty? ? Views::ExtensionTable.render_empty : (@table&.view || Views::ExtensionTable.render_empty)
        end
      end
    end

    def rebuild_table
      table_height = [@height - 6, 5].max
      @table = Views::ExtensionTable.build(@extensions, table_height)
    end

    def rebuild_calls_table
      height = [[@active_calls.size, @height - 8].min, 1].max
      @calls_table = Views::ActiveCalls.build(@active_calls, height)
    end

    def rebuild_queues_table
      height = [[@queues.size, @height - 8].min, 1].max
      @queues_table = Views::QueueTable.build(@queues, height)
    end

    def connect_cmd
      -> {
        begin
          @bridge.connect_and_login
          peers = @bridge.discover_peers
          queues = @bridge.discover_queues
          @bridge.subscribe
          Messages::ConnectionEstablished.new(
            remote: "#{@config.host}:#{@config.port}",
            peers: peers,
            queues: queues
          )
        rescue => e
          Messages::ConnectionLost.new(reason: e.message)
        end
      }
    end

    def wait_for_event_cmd
      -> { @bridge.next_event }
    end

    def tick_cmd
      Bubbletea.tick(TICK_INTERVAL) { Messages::Tick.new(at: Time.now) }
    end

    def quit_key?(msg)
      return true if msg.esc?
      return true if msg.ctrl? && msg.key_type == Bubbletea::KeyMessage::KEY_CTRL_C
      return true if msg.runes? && msg.char == "e"

      false
    end
  end
end

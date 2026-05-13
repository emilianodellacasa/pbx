# frozen_string_literal: true

require "bubbletea"
require "bubbles"
require "lipgloss"
require_relative "messages"
require_relative "views/header"
require_relative "views/extension_table"
require_relative "views/footer"
require_relative "views/disconnected_screen"
require_relative "views/info_modal"

module Pbx
  class App
    include Bubbletea::Model

    TICK_INTERVAL = 1  # seconds between "time since last change" refresh

    attr_reader :extensions, :status, :error, :width, :height, :config, :show_info,
                :system_boot_at, :last_reload_at

    def spinner_view = @spinner.view

    def initialize(bridge:, config:)
      @bridge          = bridge
      @config          = config
      @extensions      = {}
      @status          = @config.complete? ? :connecting : :disconnected
      @error           = nil
      @width           = 80
      @height          = 24
      @table           = nil
      @show_info       = false
      @spinner         = Bubbles::Spinner.new(spinner: Bubbles::Spinners::DOT)
      @system_boot_at  = nil
      @last_reload_at  = nil
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

        if @table && (@status == :connected)
          @table, table_cmd = @table.update(message)
          return [self, table_cmd]
        end

      when Bubbletea::WindowSizeMessage
        @width  = message.width
        @height = message.height
        rebuild_table if @status == :connected

      when Messages::ConnectionEstablished
        @status = :connected
        @error  = nil
        message.peers.each { |p| @extensions[p.id] = p }
        rebuild_table
        return [self, wait_for_event_cmd]

      when Messages::ConnectionLost
        @status = :lost
        @error  = message.reason
        return [self, wait_for_event_cmd]

      when Messages::PeerDiscovered
        @extensions[message.peer.id] = message.peer
        rebuild_table
        return [self, wait_for_event_cmd]

      when Messages::PeerStatusChanged
        if (peer = @extensions[message.peer_name])
          @extensions[peer.id] = Peer.new(
            id:             peer.id,
            name:           peer.name,
            ip_address:     message.ip_address || peer.ip_address,
            ip_port:        message.ip_port    || peer.ip_port,
            status:         message.status,
            type:           peer.type,
            dynamic:        peer.dynamic,
            user_agent:     peer.user_agent,
            rtt_ms:         message.rtt_ms     || peer.rtt_ms,
            last_change_at: message.at
          )
          rebuild_table
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
      body   = build_body
      footer = Views::Footer.call(self)
      Lipgloss.join_vertical(:left, header, body, footer)
    end

    private

    def build_body
      case @status
      when :disconnected
        Views::DisconnectedScreen.call(self)
      when :connecting
        body_height = [(@height - 4), 1].max
        "\n" * body_height
      else
        @extensions.empty? ? Views::ExtensionTable.render_empty : (@table&.view || Views::ExtensionTable.render_empty)
      end
    end

    def rebuild_table
      table_height = [@height - 6, 5].max
      @table = Views::ExtensionTable.build(@extensions, table_height)
    end

    def connect_cmd
      -> {
        begin
          @bridge.connect_and_login
          peers = @bridge.discover_peers
          @bridge.subscribe
          Messages::ConnectionEstablished.new(
            remote: "#{@config.host}:#{@config.port}",
            peers:  peers
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
      return true if msg.runes? && msg.char == "q"

      false
    end
  end
end

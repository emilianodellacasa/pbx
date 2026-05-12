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

    attr_reader :extensions, :status, :error, :width, :height, :config, :show_info

    def initialize(bridge:, config:)
      @bridge     = bridge
      @config     = config
      @extensions = {}
      @status     = @config.complete? ? :connecting : :disconnected
      @error      = nil
      @width      = 80
      @height     = 24
      @table      = nil
      @show_info  = false
      @spinner    = Bubbles::Spinner.new(spinner: Bubbles::Spinners::DOT)
    end

    def init
      if @config.complete?
        @spinner, spinner_cmd = @spinner.init
        [self, Bubbletea.batch(connect_cmd, wait_for_event_cmd, tick_cmd, spinner_cmd)]
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

      when Messages::LineStatusChanged
        peer = @extensions[message.peer_id] || @extensions.values.find { |p| p.extension == message.peer_id }
        if peer
          @extensions[peer.id] = Peer.new(
            id:             peer.id,
            extension:      peer.extension,
            context:        peer.context,
            label:          peer.label,
            status_code:    message.status_code,
            last_change_at: message.at
          )
          rebuild_table
        end
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
        padding = Lipgloss::Style.new.padding(1, 2)
        padding.render("#{@spinner.view}  Connecting to #{@config.host}:#{@config.port}…")
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

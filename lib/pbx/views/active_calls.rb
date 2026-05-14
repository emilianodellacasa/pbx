# frozen_string_literal: true

require "lipgloss"
require "bubbles"

module Pbx
  module Views
    module ActiveCalls
      COLUMNS = [
        { title: "Channel", width: 14 },
        { title: "State",   width: 14 },
        { title: "App",     width: 14 },
        { title: "With",    width: 18 },
        { title: "For",     width: 10 }
      ].freeze

      HEADER_STYLE   = Lipgloss::Style.new.bold(true).foreground("#f59e0b")
      SELECTED_STYLE = Lipgloss::Style.new.bold(true).foreground("#ffffff").background("#d97706")
      TITLE_STYLE    = Lipgloss::Style.new.bold(true).foreground("#f59e0b").padding(0, 1)
      SEP_STYLE      = Lipgloss::Style.new.foreground("#4b5563")

      STATE_SYMBOLS = {
        "up"       => "▶",
        "ringing"  => "◎",
        "ring"     => "◎",
        "dialing"  => "→",
        "offhook"  => "·"
      }.freeze

      OUTCOME_SYMBOLS = {
        "ANSWER"      => "▶",
        "BUSY"        => "✕",
        "NOANSWER"    => "⌀",
        "CANCEL"      => "←",
        "CHANUNAVAIL" => "✗",
        "CONGESTION"  => "!"
      }.freeze

      OUTCOME_LABELS = {
        "BUSY"        => "Busy",
        "NOANSWER"    => "No answer",
        "CANCEL"      => "Cancelled",
        "CHANUNAVAIL" => "Unavailable",
        "CONGESTION"  => "Congestion"
      }.freeze

      def self.render(calls, width, table_height)
        sep   = SEP_STYLE.render("─" * [width, 1].max)
        title = TITLE_STYLE.render("Active Calls (#{calls.size})")
        table = build(calls, table_height)
        Lipgloss.join_vertical(:left, sep, title, table.view)
      end

      def self.build(calls, table_height)
        rows = calls.values
                    .sort_by { |c| c.started_at || Time.now }
                    .map { |call|
                      [
                        short_channel(call.channel),
                        state_text(call),
                        call.dialplan_app || "—",
                        call.connected_to.to_s.empty? ? "—" : call.connected_to,
                        duration(call.started_at)
                      ]
                    }

        Bubbles::Table.new(columns: COLUMNS, rows: rows, height: table_height).tap do |t|
          t.header_style   = HEADER_STYLE
          t.selected_style = SELECTED_STYLE
        end
      end

      def self.short_channel(channel)
        return "—" unless channel

        channel.sub(/\ASIP\//i, "").split("-").first || channel
      end

      def self.state_text(call)
        return "⏸ Hold" if call.held

        if call.outcome && call.outcome != "ANSWER"
          sym   = OUTCOME_SYMBOLS.fetch(call.outcome, "?")
          label = OUTCOME_LABELS.fetch(call.outcome, call.outcome.downcase.capitalize)
          return "#{sym} #{label}"
        end

        key    = call.state.to_s.downcase
        symbol = STATE_SYMBOLS.fetch(key, "·")
        "#{symbol} #{call.state.to_s.capitalize}"
      end

      def self.duration(started_at)
        return "—" unless started_at

        secs = (Time.now - started_at).to_i
        "#{secs / 60}m #{(secs % 60).to_s.rjust(2, "0")}s"
      end
    end
  end
end

# frozen_string_literal: true

require "lipgloss"
require "bubbles"
require_relative "../status"

module Pbx
  module Views
    module ExtensionTable
      COLUMNS = [
        { title: "Peer",       width: 16 },
        { title: "Status",     width: 14 },
        { title: "IP Address", width: 17 },
        { title: "Port",       width: 6  },
        { title: "Type",       width: 8  },
        { title: "RTT (ms)",   width: 9  },
        { title: "Changed",    width: 12 }
      ].freeze

      HEADER_STYLE   = Lipgloss::Style.new.bold(true).foreground("#a78bfa")
      SELECTED_STYLE = Lipgloss::Style.new.bold(true).foreground("#ffffff").background("#7c3aed")

      EMPTY_STYLE = Lipgloss::Style.new.foreground("#6b7280").italic(true).padding(2, 4)

      STATUS_DOTS = {
        "registered"   => "●",
        "reachable"    => "●",
        "lagged"       => "◑",
        "unreachable"  => "○",
        "unregistered" => "·",
        "unmonitored"  => "·",
        "unknown"      => "·"
      }.freeze

      def self.build(peers, table_height)
        rows = peers.values.sort_by(&:name).map { |peer|
          [
            peer.name,
            status_text(peer.status),
            peer.ip_address || "—",
            peer.ip_port&.to_s || "—",
            peer.type || "—",
            peer.rtt_ms&.to_s || "—",
            since(peer.last_change_at)
          ]
        }

        Bubbles::Table.new(columns: COLUMNS, rows: rows, height: table_height).tap do |t|
          t.header_style   = HEADER_STYLE
          t.selected_style = SELECTED_STYLE
        end
      end

      def self.render_empty
        EMPTY_STYLE.render("No SIP peers discovered yet…")
      end

      # Plain-text status for table cells — ANSI codes break Bubbles::Table width math.
      def self.status_text(status)
        dot   = STATUS_DOTS.fetch(status.to_s, "·")
        label = Status.describe(status)
        "#{dot} #{label}"
      end

      # ANSI-colored status for use outside the table (info panels, etc.).
      def self.colorized_status(status)
        color = Status.color(status)
        label = Status.describe(status)
        Lipgloss::Style.new.foreground(color).bold(true).render(label)
      end

      def self.since(time)
        return "—" unless time

        secs = (Time.now - time).to_i
        return "Just now"           if secs < 5
        return "#{secs}s ago"      if secs < 60
        return "#{secs / 60}m ago" if secs < 3600

        "#{secs / 3600}h ago"
      end
    end
  end
end

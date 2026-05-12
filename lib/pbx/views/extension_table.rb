# frozen_string_literal: true

require "lipgloss"
require "bubbles"
require_relative "../status"

module Pbx
  module Views
    module ExtensionTable
      COLUMNS = [
        { title: "Extension", width: 14 },
        { title: "Label",     width: 24 },
        { title: "Status",    width: 16 },
        { title: "Context",   width: 18 },
        { title: "Changed",   width: 16 }
      ].freeze

      HEADER_STYLE   = Lipgloss::Style.new.bold(true).foreground("#a78bfa")
      SELECTED_STYLE = Lipgloss::Style.new.bold(true).foreground("#ffffff").background("#7c3aed")

      EMPTY_STYLE = Lipgloss::Style.new.foreground("#6b7280").italic(true).padding(2, 4)

      def self.build(extensions, table_height)
        rows = extensions.values.sort_by(&:extension).map { |peer|
          [
            peer.extension,
            peer.label,
            colorized_status(peer.status_code),
            peer.context,
            since(peer.last_change_at)
          ]
        }

        Bubbles::Table.new(columns: COLUMNS, rows: rows, height: table_height).tap do |t|
          t.header_style   = HEADER_STYLE
          t.selected_style = SELECTED_STYLE
        end
      end

      def self.render_empty
        EMPTY_STYLE.render("No extensions discovered yet…")
      end

      def self.colorized_status(code)
        color = Status.color(code)
        label = Status.describe(code)
        Lipgloss::Style.new.foreground(color).bold(true).render(label)
      end

      def self.since(time)
        return "—" unless time

        secs = (Time.now - time).to_i
        return "just now"       if secs < 5
        return "#{secs}s ago"   if secs < 60
        return "#{secs / 60}m ago" if secs < 3600

        "#{secs / 3600}h ago"
      end
    end
  end
end

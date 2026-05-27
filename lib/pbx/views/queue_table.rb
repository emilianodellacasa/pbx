# frozen_string_literal: true

require "lipgloss"
require "bubbles"

module Pbx
  module Views
    module QueueTable
      COLUMNS = [
        {title: "Queue", width: 16},
        {title: "Strategy", width: 12},
        {title: "Waiting", width: 9},
        {title: "Agents", width: 8},
        {title: "Completed", width: 11},
        {title: "Abandoned", width: 11},
        {title: "Avg Hold", width: 10}
      ].freeze

      HEADER_STYLE = Lipgloss::Style.new.bold(true).foreground("#34d399")
      SELECTED_STYLE = Lipgloss::Style.new.bold(true).foreground("#ffffff").background("#059669")
      TITLE_STYLE = Lipgloss::Style.new.bold(true).foreground("#34d399").padding(0, 1)
      SEP_STYLE = Lipgloss::Style.new.foreground("#4b5563")
      EMPTY_STYLE = Lipgloss::Style.new.foreground("#6b7280").italic(true).padding(2, 4)

      def self.render(queues, width, table_height)
        return EMPTY_STYLE.render("No queues discovered yet…") if queues.empty?

        sep = SEP_STYLE.render("─" * [width, 1].max)
        title = TITLE_STYLE.render("Queues (#{queues.size})")
        table = build(queues, table_height)
        Lipgloss.join_vertical(:left, sep, title, table.view)
      end

      def self.build(queues, table_height)
        rows = queues.values.sort_by(&:name).map { |q|
          avail = q.members.values.count(&:available?)
          total = q.members.size
          [
            q.name,
            q.strategy,
            q.calls_waiting.to_s,
            "#{avail}/#{total}",
            q.completed.to_s,
            q.abandoned.to_s,
            format_holdtime(q.holdtime)
          ]
        }

        Bubbles::Table.new(columns: COLUMNS, rows: rows, height: table_height).tap do |t|
          t.header_style = HEADER_STYLE
          t.selected_style = SELECTED_STYLE
        end
      end

      def self.format_holdtime(secs)
        return "—" if secs.nil? || secs == 0

        "#{secs / 60}m #{(secs % 60).to_s.rjust(2, "0")}s"
      end
    end
  end
end

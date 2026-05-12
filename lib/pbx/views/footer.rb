# frozen_string_literal: true

require "lipgloss"

module Pbx
  module Views
    module Footer
      HINT_STYLE = Lipgloss::Style.new.foreground("#6b7280").faint(true)
      KEY_STYLE  = Lipgloss::Style.new.foreground("#9ca3af").bold(true)
      SEP_STYLE  = Lipgloss::Style.new.foreground("#4b5563")

      HINTS = [
        ["↑/↓", "scroll"],
        ["i", "info"],
        ["q/Esc", "quit"]
      ].freeze

      def self.call(state)
        sep   = SEP_STYLE.render("─" * (state.width > 0 ? state.width : 80))
        hints = HINTS.map { |key, label|
          "#{KEY_STYLE.render(key)} #{HINT_STYLE.render(label)}"
        }.join("  ")

        right = if state.status == :disconnected
                  HINT_STYLE.render("pbx monitor --host HOST --user USER --secret SECRET")
                else
                  HINT_STYLE.render("#{state.extensions.size} extension(s)")
                end

        bar = Lipgloss.join_horizontal(:center, hints, "   ", right)
        Lipgloss.join_vertical(:left, sep, bar)
      end
    end
  end
end

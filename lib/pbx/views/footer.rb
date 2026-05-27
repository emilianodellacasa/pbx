# frozen_string_literal: true

require "lipgloss"

module Pbx
  module Views
    module Footer
      HINT_STYLE = Lipgloss::Style.new.foreground("#6b7280").faint(true)
      KEY_STYLE = Lipgloss::Style.new.foreground("#9ca3af").bold(true)
      SEP_STYLE = Lipgloss::Style.new.foreground("#4b5563")

      ACTIVE_KEY_STYLE = Lipgloss::Style.new.foreground("#f59e0b").bold(true)

      def self.call(state)
        sep = SEP_STYLE.render("─" * ((state.width > 0) ? state.width : 80))
        hints = build_hints(state)

        right = if state.status == :disconnected
          HINT_STYLE.render("pbx monitor --host HOST --user USER --secret SECRET")
        else
          HINT_STYLE.render("#{state.extensions.size} extension(s)")
        end

        bar = Lipgloss.join_horizontal(:center, hints, "   ", right)
        Lipgloss.join_vertical(:left, sep, bar)
      end

      def self.build_hints(state)
        connected = state.status == :connected

        tab_peers = tab_hint("p", "peers", connected && state.view_mode == :peers)
        tab_calls = tab_hint("c", "calls", connected && state.view_mode == :calls)
        tab_queues = tab_hint("q", "queues", connected && state.view_mode == :queues)

        static = [
          "#{KEY_STYLE.render("↑/↓")} #{HINT_STYLE.render("scroll")}",
          "#{KEY_STYLE.render("i")} #{HINT_STYLE.render("info")}",
          "#{KEY_STYLE.render("e/Esc")} #{HINT_STYLE.render("quit")}"
        ]

        ([tab_peers, tab_calls, tab_queues] + static).join("  ")
      end

      def self.tab_hint(key, label, active)
        key_s = active ? ACTIVE_KEY_STYLE.render(key) : KEY_STYLE.render(key)
        lbl_s = active ? ACTIVE_KEY_STYLE.render(label) : HINT_STYLE.render(label)
        "#{key_s} #{lbl_s}"
      end
    end
  end
end

# frozen_string_literal: true

require "lipgloss"

module Pbx
  module Views
    module Header
      TITLE_STYLE = Lipgloss::Style.new
        .bold(true)
        .foreground("#7c3aed")
        .padding(0, 1)

      STATUS_DISCONNECTED_STYLE = Lipgloss::Style.new.foreground("#6b7280").italic(true)
      STATUS_CONNECTING_STYLE   = Lipgloss::Style.new.foreground("#f59e0b").italic(true)
      STATUS_CONNECTED_STYLE    = Lipgloss::Style.new.foreground("#22c55e").bold(true)
      STATUS_LOST_STYLE         = Lipgloss::Style.new.foreground("#ef4444").bold(true)

      SEPARATOR_STYLE = Lipgloss::Style.new.foreground("#4b5563")

      def self.call(state)
        title  = TITLE_STYLE.render("PBX Monitor")
        remote = "#{state.config.host}:#{state.config.port}"
        status = case state.status
                 when :disconnected then STATUS_DISCONNECTED_STYLE.render("◌  Disconnected")
                 when :connecting   then STATUS_CONNECTING_STYLE.render("Connecting to #{remote}…")
                 when :connected    then STATUS_CONNECTED_STYLE.render("● #{remote}")
                 when :lost         then STATUS_LOST_STYLE.render("✗ #{remote}  #{state.error}")
                 end

        line = Lipgloss.join_horizontal(:center, title, "  ", status)
        sep  = SEPARATOR_STYLE.render("─" * (state.width > 0 ? state.width : 80))
        Lipgloss.join_vertical(:left, line, sep)
      end
    end
  end
end

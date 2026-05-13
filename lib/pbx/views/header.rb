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
      SYSINFO_STYLE   = Lipgloss::Style.new.foreground("#6b7280")

      def self.call(state)
        title  = TITLE_STYLE.render("PBX Monitor")
        remote = "#{state.config.host}:#{state.config.port}"
        status = case state.status
                 when :disconnected then STATUS_DISCONNECTED_STYLE.render("◌  Disconnected")
                 when :connecting   then STATUS_CONNECTING_STYLE.render("#{state.spinner_view}  Connecting to #{remote}…")
                 when :connected    then STATUS_CONNECTED_STYLE.render("● #{remote}")
                 when :lost         then STATUS_LOST_STYLE.render("✗ #{remote}  #{state.error}")
                 end

        sysinfo = build_sysinfo(state)
        line    = if sysinfo
                    Lipgloss.join_horizontal(:center, title, "  ", status, "  ", sysinfo)
                  else
                    Lipgloss.join_horizontal(:center, title, "  ", status)
                  end
        sep = SEPARATOR_STYLE.render("─" * (state.width > 0 ? state.width : 80))
        Lipgloss.join_vertical(:left, line, sep)
      end

      def self.build_sysinfo(state)
        return nil unless state.system_boot_at || state.last_reload_at

        parts = []
        parts << "Up #{format_duration((Time.now - state.system_boot_at).to_i)}" if state.system_boot_at
        parts << "Reload #{format_duration((Time.now - state.last_reload_at).to_i)}" if state.last_reload_at
        SYSINFO_STYLE.render(parts.join("  ·  "))
      end

      def self.format_duration(secs)
        d = secs / 86_400
        h = (secs % 86_400) / 3_600
        m = (secs % 3_600) / 60

        parts = []
        parts << "#{d}d" if d > 0
        parts << "#{h}h" if h > 0 || d > 0
        parts << "#{m}m"
        parts.join(" ")
      end
    end
  end
end

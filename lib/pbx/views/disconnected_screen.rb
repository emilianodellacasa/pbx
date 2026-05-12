# frozen_string_literal: true

require "lipgloss"

module Pbx
  module Views
    module DisconnectedScreen
      ICON_STYLE = Lipgloss::Style.new
        .foreground("#4b5563")
        .bold(true)

      TITLE_STYLE = Lipgloss::Style.new
        .foreground("#9ca3af")
        .bold(true)

      BODY_STYLE = Lipgloss::Style.new
        .foreground("#6b7280")

      CODE_STYLE = Lipgloss::Style.new
        .foreground("#a78bfa")
        .bold(true)

      HINT_STYLE = Lipgloss::Style.new
        .foreground("#4b5563")
        .italic(true)

      BOX_STYLE = Lipgloss::Style.new
        .border(:rounded)
        .border_foreground("#374151")
        .padding(1, 3)
        .margin(1, 2)

      def self.call(state)
        missing = missing_params(state.config)

        lines = [
          ICON_STYLE.render("◌") + "  " + TITLE_STYLE.render("No connection configured"),
          "",
          BODY_STYLE.render("Missing parameters: ") + missing.map { |p| CODE_STYLE.render("--#{p}") }.join("  "),
          "",
          BODY_STYLE.render("Example:"),
          "  " + CODE_STYLE.render("pbx monitor --host 192.168.1.10 --user admin --secret s3cret"),
          "",
          HINT_STYLE.render("or use a config file:"),
          "  " + CODE_STYLE.render("pbx monitor --config /path/to/pbx.yml")
        ]

        BOX_STYLE.render(lines.join("\n"))
      end

      def self.missing_params(config)
        params = []
        params << "host"   if config.host == "127.0.0.1"
        params << "user"   if config.user.to_s.strip.empty?
        params << "secret" if config.secret.to_s.strip.empty?
        params
      end
    end
  end
end

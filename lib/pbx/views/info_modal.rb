# frozen_string_literal: true

require "lipgloss"
require_relative "../version"

module Pbx
  module Views
    module InfoModal
      TITLE_STYLE = Lipgloss::Style.new
        .bold(true)
        .foreground("#a78bfa")
        .align(:center)

      VERSION_STYLE = Lipgloss::Style.new
        .foreground("#6b7280")
        .align(:center)

      LABEL_STYLE = Lipgloss::Style.new
        .foreground("#9ca3af")

      VALUE_STYLE = Lipgloss::Style.new
        .foreground("#e5e7eb")
        .bold(true)

      URL_STYLE = Lipgloss::Style.new
        .foreground("#60a5fa")
        .underline(true)

      HINT_STYLE = Lipgloss::Style.new
        .foreground("#4b5563")
        .italic(true)
        .align(:center)

      BOX_STYLE = Lipgloss::Style.new
        .border(:rounded)
        .border_foreground("#7c3aed")
        .padding(1, 4)

      REPO_URL = "https://github.com/emilianodellacasa/pbx"

      def self.call(state)
        inner_width = 36

        title = TITLE_STYLE.width(inner_width).render("PBX Monitor")
        version = VERSION_STYLE.width(inner_width).render("v#{Pbx::VERSION}")

        divider = Lipgloss::Style.new.foreground("#374151").render("─" * inner_width)

        author_row = "#{LABEL_STYLE.render("Author")}  #{VALUE_STYLE.render("Emiliano Della Casa")}"
        repo_row = "#{LABEL_STYLE.render("GitHub")}  #{URL_STYLE.render(REPO_URL)}"

        hint = HINT_STYLE.width(inner_width).render("Press any key to close")

        content = Lipgloss.join_vertical(
          :center,
          title,
          version,
          "",
          divider,
          "",
          author_row,
          repo_row,
          "",
          hint
        )

        modal = BOX_STYLE.render(content)

        w = (state.width > 0) ? state.width : 80
        h = (state.height > 0) ? state.height : 24
        Lipgloss.place(w, h, :center, :center, modal)
      end
    end
  end
end

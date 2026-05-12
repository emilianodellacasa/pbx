# frozen_string_literal: true

require "ruby-asterisk"

module Pbx
  module Status
    STATUS_COLORS = {
      "0"  => "#22c55e",  # Idle — green
      "1"  => "#ef4444",  # In Use — red
      "2"  => "#ef4444",  # Busy — red
      "3"  => "#6b7280",  # Unavailable — gray
      "4"  => "#f59e0b",  # Ringing — amber
      "5"  => "#a78bfa",  # On Hold — purple
      "-1" => "#6b7280"   # Not found — gray
    }.freeze

    def self.describe(code)
      RubyAsterisk::DESCRIPTIVE_STATUS[code.to_s] || "Unknown"
    end

    def self.color(code)
      STATUS_COLORS[code.to_s] || "#6b7280"
    end
  end
end

# frozen_string_literal: true

module Pbx
  module Status
    STATUS_COLORS = {
      "registered" => "#22c55e",
      "reachable" => "#22c55e",
      "lagged" => "#f59e0b",
      "unreachable" => "#ef4444",
      "unregistered" => "#6b7280",
      "unmonitored" => "#6b7280",
      "unknown" => "#6b7280"
    }.freeze

    STATUS_LABELS = {
      "registered" => "Registered",
      "reachable" => "Reachable",
      "lagged" => "Lagged",
      "unreachable" => "Unreachable",
      "unregistered" => "Unregistered",
      "unmonitored" => "Unmonitored",
      "unknown" => "Unknown"
    }.freeze

    def self.describe(status)
      STATUS_LABELS[status.to_s.downcase] || status.to_s.capitalize
    end

    def self.color(status)
      STATUS_COLORS[status.to_s.downcase] || "#6b7280"
    end

    # Normalises the raw AMI Status string from SIPpeers/PeerStatus into a
    # lowercase key used by describe/color.
    def self.from_sip(raw)
      return "unknown" unless raw

      s = raw.to_s.downcase
      return "registered" if s.start_with?("ok")
      return "unreachable" if s.include?("unreachable")
      return "lagged" if s.include?("lagged")
      return "unregistered" if s.include?("unregistered")
      return "unmonitored" if s.include?("unmonitored")
      return "registered" if s.include?("registered") || s.include?("reachable")

      "unknown"
    end

    QUEUE_MEMBER_STATES = {
      "1" => "not_in_use",
      "2" => "in_use",
      "3" => "busy",
      "5" => "unavailable",
      "6" => "ringing",
      "8" => "on_hold"
    }.freeze

    def self.queue_member_state(code)
      QUEUE_MEMBER_STATES[code.to_s] || "unknown"
    end

    # Extracts the RTT in milliseconds from strings like "OK (5 ms)".
    def self.rtt_from_sip(raw)
      return nil unless raw

      match = raw.match(/\((\d+)\s*ms\)/i)
      match ? match[1].to_i : nil
    end
  end
end

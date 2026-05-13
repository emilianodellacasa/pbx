# frozen_string_literal: true

module Pbx
  Peer = Data.define(:id, :name, :ip_address, :ip_port, :status, :type, :dynamic, :user_agent, :rtt_ms, :last_change_at)
end

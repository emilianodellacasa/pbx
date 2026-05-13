# frozen_string_literal: true

require "bubbletea"

module Pbx
  module Messages
    class PeerDiscovered < Bubbletea::Message
      attr_reader :peer

      def initialize(peer:)
        super()
        @peer = peer
      end
    end

    class PeerStatusChanged < Bubbletea::Message
      attr_reader :peer_name, :status, :ip_address, :ip_port, :rtt_ms, :at

      def initialize(peer_name:, status:, ip_address: nil, ip_port: nil, rtt_ms: nil, at:)
        super()
        @peer_name  = peer_name
        @status     = status
        @ip_address = ip_address
        @ip_port    = ip_port
        @rtt_ms     = rtt_ms
        @at         = at
      end
    end

    class ConnectionEstablished < Bubbletea::Message
      attr_reader :remote, :peers

      def initialize(remote:, peers:)
        super()
        @remote = remote
        @peers  = peers
      end
    end

    class ConnectionLost < Bubbletea::Message
      attr_reader :reason

      def initialize(reason:)
        super()
        @reason = reason
      end
    end

    class AmiError < Bubbletea::Message
      attr_reader :error

      def initialize(error:)
        super()
        @error = error
      end
    end

    class Tick < Bubbletea::Message
      attr_reader :at

      def initialize(at:)
        super()
        @at = at
      end
    end

    class SystemInfo < Bubbletea::Message
      attr_reader :uptime_secs, :last_reload_secs, :received_at

      def initialize(uptime_secs:, last_reload_secs:, received_at:)
        super()
        @uptime_secs      = uptime_secs
        @last_reload_secs = last_reload_secs
        @received_at      = received_at
      end
    end
  end
end

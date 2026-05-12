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

    class LineStatusChanged < Bubbletea::Message
      attr_reader :peer_id, :status_code, :at

      def initialize(peer_id:, status_code:, at:)
        super()
        @peer_id     = peer_id
        @status_code = status_code
        @at          = at
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
  end
end

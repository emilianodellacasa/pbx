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

      def initialize(peer_name:, status:, at:, ip_address: nil, ip_port: nil, rtt_ms: nil)
        super()
        @peer_name = peer_name
        @status = status
        @ip_address = ip_address
        @ip_port = ip_port
        @rtt_ms = rtt_ms
        @at = at
      end
    end

    class ConnectionEstablished < Bubbletea::Message
      attr_reader :remote, :peers, :queues

      def initialize(remote:, peers:, queues: {})
        super()
        @remote = remote
        @peers = peers
        @queues = queues
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

    class CallStarted < Bubbletea::Message
      attr_reader :uniqueid, :channel, :caller_id, :caller_name, :state, :started_at

      def initialize(uniqueid:, channel:, caller_id:, caller_name:, state:, started_at:)
        super()
        @uniqueid = uniqueid
        @channel = channel
        @caller_id = caller_id
        @caller_name = caller_name
        @state = state
        @started_at = started_at
      end
    end

    class CallEnded < Bubbletea::Message
      attr_reader :uniqueid

      def initialize(uniqueid:)
        super()
        @uniqueid = uniqueid
      end
    end

    class CallStateChanged < Bubbletea::Message
      attr_reader :uniqueid, :state, :connected_to

      def initialize(uniqueid:, state:, connected_to: nil)
        super()
        @uniqueid = uniqueid
        @state = state
        @connected_to = connected_to
      end
    end

    class DialCompleted < Bubbletea::Message
      attr_reader :uniqueid, :dial_status

      def initialize(uniqueid:, dial_status:)
        super()
        @uniqueid = uniqueid
        @dial_status = dial_status
      end
    end

    class CallHeld < Bubbletea::Message
      attr_reader :uniqueid

      def initialize(uniqueid:)
        super()
        @uniqueid = uniqueid
      end
    end

    class CallUnheld < Bubbletea::Message
      attr_reader :uniqueid

      def initialize(uniqueid:)
        super()
        @uniqueid = uniqueid
      end
    end

    class CallDialplanUpdate < Bubbletea::Message
      attr_reader :uniqueid, :context, :exten, :application

      def initialize(uniqueid:, context:, exten:, application:)
        super()
        @uniqueid = uniqueid
        @context = context
        @exten = exten
        @application = application
      end
    end

    class QueueCallerCountChanged < Bubbletea::Message
      attr_reader :queue, :count

      def initialize(queue:, count:)
        super()
        @queue = queue
        @count = count
      end
    end

    class QueueCallerAbandoned < Bubbletea::Message
      attr_reader :queue

      def initialize(queue:)
        super()
        @queue = queue
      end
    end

    class QueueMemberUpdated < Bubbletea::Message
      attr_reader :queue, :interface, :name, :status, :paused

      def initialize(queue:, interface:, name:, status:, paused:)
        super()
        @queue = queue
        @interface = interface
        @name = name
        @status = status
        @paused = paused
      end
    end

    class QueueMemberGone < Bubbletea::Message
      attr_reader :queue, :interface

      def initialize(queue:, interface:)
        super()
        @queue = queue
        @interface = interface
      end
    end

    class SystemInfo < Bubbletea::Message
      attr_reader :uptime_secs, :last_reload_secs, :received_at

      def initialize(uptime_secs:, last_reload_secs:, received_at:)
        super()
        @uptime_secs = uptime_secs
        @last_reload_secs = last_reload_secs
        @received_at = received_at
      end
    end
  end
end

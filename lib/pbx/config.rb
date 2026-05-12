# frozen_string_literal: true

require "yaml"

module Pbx
  module Config
    class Error < StandardError; end

    Value = Data.define(:host, :port, :user, :secret, :context, :reconnect_backoff) do
      def complete?
        user.to_s.strip.length.positive? && secret.to_s.strip.length.positive?
      end
    end

    DEFAULTS = {
      host:              "127.0.0.1",
      port:              5038,
      user:              nil,
      secret:            nil,
      context:           "default",
      reconnect_backoff: [1, 2, 5, 10]
    }.freeze

    def self.load(cli: {})
      from_yaml = cli[:config] ? load_yaml(cli[:config]) : {}
      merged    = DEFAULTS.merge(from_yaml).merge(compact(cli).except(:config))
      Value.new(**merged)
    end

    def self.load_yaml(path)
      raw = YAML.safe_load_file(path, symbolize_names: true)
      raw.slice(:host, :port, :user, :secret, :context, :reconnect_backoff)
    rescue Errno::ENOENT
      raise Error, "Config file not found: #{path}"
    rescue Psych::Exception => e
      raise Error, "Invalid YAML config: #{e.message}"
    end

    def self.compact(hash)
      hash.reject { |_, v| v.nil? }
    end

    private_class_method :load_yaml, :compact
  end
end

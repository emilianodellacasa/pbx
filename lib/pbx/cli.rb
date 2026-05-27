# frozen_string_literal: true

require "thor"
require "bubbletea"
require_relative "version"
require_relative "config"
require_relative "ami_bridge"
require_relative "app"

module Pbx
  class CLI < Thor
    desc "monitor", "Open the TUI and monitor Asterisk extension status"
    long_desc <<~DESC
      Connects to an Asterisk PBX via AMI, auto-discovers SIP/PJSIP extensions,
      and displays real-time line status in a terminal UI.

      Connection parameters can be supplied via CLI flags or a YAML config file
      (use --config). CLI flags always override YAML values.
    DESC
    option :host, type: :string, desc: "AMI hostname or IP (default: 127.0.0.1)"
    option :port, type: :numeric, desc: "AMI port (default: 5038)"
    option :user, type: :string, desc: "AMI username"
    option :secret, type: :string, desc: "AMI secret/password"
    option :config, type: :string, aliases: "-c", desc: "Path to YAML config file"
    option :debug, type: :boolean, default: false, desc: "Write AMI debug log to /tmp/pbx_debug.log"
    def monitor
      cli_opts = options.to_h.transform_keys(&:to_sym)
      debug = cli_opts.delete(:debug) { false }
      cfg = Config.load(cli: cli_opts)
      bridge = AmiBridge.new(cfg, debug: debug)
      Bubbletea.run(App.new(bridge: bridge, config: cfg), alt_screen: true)
    rescue Config::Error => e
      warn "Error: #{e.message}"
      exit 1
    ensure
      bridge&.shutdown
    end

    desc "version", "Print pbx version"
    def version
      puts "pbx #{Pbx::VERSION}"
    end

    def self.exit_on_failure? = true
  end
end

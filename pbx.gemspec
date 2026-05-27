# frozen_string_literal: true

require_relative "lib/pbx/version"

Gem::Specification.new do |spec|
  spec.name = "pbx"
  spec.version = Pbx::VERSION
  spec.authors = ["Emiliano Della Casa"]
  spec.email = ["emiliano.dellacasa@nexteering.com"]

  spec.summary = "TUI Asterisk PBX line monitor"
  spec.description = "A terminal UI for monitoring Asterisk PBX extension status via AMI."
  spec.homepage = "https://github.com/emilianodellacasa/pbx"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.bindir = "exe"
  spec.executables = ["pbx"]
  spec.files = Dir["{lib,exe,examples}/**/*", "LICENSE", "README.md"]
  spec.require_paths = ["lib"]

  # ruby-asterisk is declared only in the Gemfile (as a git dependency on a
  # custom branch) and intentionally omitted here. Once the gem is published
  # to RubyGems, move it here as: spec.add_dependency "ruby-asterisk", "~> 1.0"
  spec.add_dependency "thor", "~> 1.3"
  spec.add_dependency "bubbletea", "~> 0.1"
  spec.add_dependency "lipgloss", "~> 0.2"
  spec.add_dependency "bubbles", "~> 0.1"
  spec.add_dependency "bubblezone", "~> 0.1"

  spec.add_development_dependency "rspec", "~> 3.13"
  spec.add_development_dependency "rake", "~> 13.2"
  spec.add_development_dependency "standard", "~> 1.40"
  spec.add_development_dependency "pry", "~> 0.15"
end

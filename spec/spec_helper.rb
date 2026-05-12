# frozen_string_literal: true

ENV["NO_COLOR"] = "1"

require "bundler/setup"
require "pbx"

Dir[File.join(__dir__, "support/**/*.rb")].each { |f| require f }

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.order = :random
  config.filter_run_when_matching :focus
end

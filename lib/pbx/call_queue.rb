# frozen_string_literal: true

module Pbx
  CallQueue = Data.define(:name, :strategy, :calls_waiting, :completed, :abandoned, :holdtime, :last_holdtime, :members) do
    def initialize(name:, strategy:, calls_waiting:, completed:, abandoned:, holdtime:, members:, last_holdtime: nil)
      super
    end
  end
end

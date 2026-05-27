# frozen_string_literal: true

module Pbx
  CallQueue = Data.define(:name, :strategy, :calls_waiting, :completed, :abandoned, :holdtime, :members)
end

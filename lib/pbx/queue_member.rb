# frozen_string_literal: true

module Pbx
  QueueMember = Data.define(:queue, :name, :interface, :status, :paused) do
    def available? = status == "not_in_use" && !paused
  end
end

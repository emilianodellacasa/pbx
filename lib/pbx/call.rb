# frozen_string_literal: true

module Pbx
  Call = Data.define(
    :uniqueid, :channel, :caller_id, :caller_name,
    :connected_to, :state, :started_at,
    :outcome, :held, :dialplan_app, :dialplan_exten
  )
end

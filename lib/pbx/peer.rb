# frozen_string_literal: true

module Pbx
  Peer = Data.define(:id, :extension, :context, :label, :status_code, :last_change_at)
end

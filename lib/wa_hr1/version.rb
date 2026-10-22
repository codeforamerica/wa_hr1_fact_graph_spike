# frozen_string_literal: true

module WaHr1
  VERSION = "0.1.0"

  # The JSON protocol between this gem's wa-hr1-evaluate command and its callers (ADR-0003 in
  # samesite2026-app-02). Bump it whenever the input or output shape changes incompatibly.
  PROTOCOL_VERSION = 2
end

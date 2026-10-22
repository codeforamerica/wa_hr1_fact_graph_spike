# frozen_string_literal: true

require_relative "../lib/wa_hr1"

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |c| c.syntax = :expect }
end

def unknown
  be_a(FactGraph::Error)
end

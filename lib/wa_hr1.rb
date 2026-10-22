# frozen_string_literal: true

require "fact_graph"
require "active_support/concern"

require_relative "wa_hr1/logic"
require_relative "wa_hr1/unknowns"
require_relative "wa_hr1/macros"

require_relative "wa_hr1/facts/renewer_facts"
require_relative "wa_hr1/facts/household_facts"
require_relative "wa_hr1/facts/income_facts"
require_relative "wa_hr1/facts/work_requirement_facts"

require_relative "wa_hr1/graphs/base"
require_relative "wa_hr1/graphs/states/wa"
require_relative "wa_hr1/graphs/wa/income_standards_oct_2026"

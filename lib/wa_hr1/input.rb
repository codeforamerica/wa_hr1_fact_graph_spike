# frozen_string_literal: true

module WaHr1
  # Rules for building the graph's input.
  #
  # Hash sections hold answers to separate questions. Always send them, as {} if nothing is known.
  # If one is missing entirely, every question inside it fails as "the section is missing," and the
  # next-question walker can only report the section, not the questions in it.
  #
  # List sections (household_members, months) are different: an empty list is an answer ("nobody
  # else in the household"). Send a list only once you know what's in it; while it's missing, the
  # walker asks for it.
  module Input
    HASH_SECTIONS = %i[renewer work_requirement].freeze
    LIST_SECTIONS = %i[household_members months].freeze

    module_function

    def with_sections(input)
      HASH_SECTIONS.to_h { [_1, {}] }.merge(input)
    end
  end
end

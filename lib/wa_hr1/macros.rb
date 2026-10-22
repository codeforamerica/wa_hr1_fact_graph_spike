# frozen_string_literal: true

module WaHr1
  # Shorthand for facts that are just "any of" or "all of" other facts:
  #
  #   all_of_fact :renewer_uses_tax_filer_rules,
  #     dep(:expects_to_file_taxes, from: :renewer),
  #     no(:expects_to_be_claimed_as_dependent, from: :renewer)
  #
  # A bare symbol is a dependency in the same module. Pass per_entity: to make a per-entity fact.
  # Use gated_all_of_fact when each dependency is a follow-up to the ones before it (see
  # WaHr1::Logic.gated_all_of); then the order of dependencies is the order of questions.
  module Macros
    def dep(fact, from: nil) = {fact:, from:, negate: false}

    def no(fact, from: nil) = {fact:, from:, negate: true}

    def any_of_fact(name, *deps, **) = combination_fact(name, :any_of, deps, **)

    def all_of_fact(name, *deps, **) = combination_fact(name, :all_of, deps, **)

    def gated_all_of_fact(name, *deps, **) = combination_fact(name, :gated_all_of, deps, **)

    private

    def combination_fact(name, combinator, deps, **fact_options)
      deps = deps.map { |d| d.is_a?(Hash) ? d : dep(d) }
      fact(name, allow_unmet_dependencies: true, **fact_options) do
        deps.each { |d| dependency d[:fact], from: d[:from] }

        proc do
          values = deps.map do |d|
            value = data[:dependencies][d[:fact]]
            d[:negate] ? negate(value) : value
          end
          send(combinator, values)
        end
      end
    end
  end
end

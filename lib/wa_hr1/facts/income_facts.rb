# frozen_string_literal: true

# Countable household income for each month, and the income limit for the renewal month.
#
# Income is reported per month as a list of items, each tagged with whose it is (no
# household_member means the renewer's own). The household module decides whose income counts;
# this module decides which kinds of income count and converts pay frequencies to monthly amounts.
module IncomeFacts
  extend ActiveSupport::Concern

  # Each type is counted or excluded by rule, so the agent only has to sort what people say into
  # these types; it never decides what counts.
  INCOME_TYPES = {
    "wages" => :counted,
    "self_employment" => :counted, # net earnings
    "unemployment" => :counted,
    "social_security" => :counted_unless_child_or_tax_dependent, # dependents' benefits don't count (WAC 182-509-0360(1))
    "pension_or_retirement" => :counted,
    "scholarship_for_living_expenses" => :counted, # WAC 182-509-0335
    "other_taxable" => :counted,
    "educational_benefit_for_education_expenses" => :excluded, # Pell grants, loans, VA education, etc. (WAC 182-509-0335)
    "work_study" => :excluded, # WAC 182-509-0335(5)
    "american_indian_alaska_native_excluded" => :excluded, # WAC 182-509-0340
    "child_support_received" => :excluded, # not part of MAGI
    "ssi" => :excluded # not part of MAGI
  }.freeze

  # Monthly amount = amount × factor (WAC 182-509-0310). One-time amounts, including lump sums, count
  # only in the month received (WAC 182-509-0375).
  FREQUENCY_FACTORS = {
    "monthly" => 1r,
    "twice_monthly" => 2r,
    "every_two_weeks" => Rational(215, 100),
    "weekly" => Rational(43, 10),
    "yearly" => Rational(1, 12),
    "one_time" => 1r
  }.freeze

  MONTH_FORMAT = /\A\d{4}-(0[1-9]|1[0-2])\z/

  # A person's value from a renewer fact or a per-member list, or nil if it isn't known yet.
  def self.known_or_nil(value, member = nil)
    return nil if value.is_a?(FactGraph::Error)

    member.nil? ? value : value[member]
  end

  # What countable income is waiting on for one item whose status isn't known yet.
  def self.unknowns_for_item(item, deps)
    member = item[:household_member]
    needed = []
    if item[:person_income_counts].nil?
      needed << member_unknown(deps, member, :income_counts_by_member, :income_counts, :renewer_income_counts)
    end
    if item[:type_counts].nil?
      needed << member_unknown(deps, member, :is_child_or_tax_dependent_by_member, :is_child_or_tax_dependent, :renewer_is_child_or_tax_dependent)
    end
    needed
  end

  def self.member_unknown(deps, member, list_fact, member_fact, renewer_fact)
    return deps[renewer_fact] if member.nil?

    list = deps[list_fact]
    return list if list.is_a?(FactGraph::Error) # we don't know who's in the household list yet
    if member >= list.size
      return FactGraph::Error.new(fact_bad_inputs: {[:household_members] => Set["has no member #{member}, which an income item refers to"]}, fact_dependency_unmet: {})
    end

    FactGraph::Error.new(fact_bad_inputs: {}, fact_dependency_unmet: {household_members: [[member_fact, member]]})
  end

  included do
    in_module :months do
      fact :month, per_entity: :months do
        input :month, per_entity: true, value: :string, format?: MONTH_FORMAT
      end

      fact :income_items, per_entity: :months do
        input :income_items, per_entity: true do
          required(:income_items).array(:hash) do
            optional(:household_member).value(:integer, gteq?: 0)
            required(:type).value(:string, included_in?: INCOME_TYPES.keys)
            required(:amount_cents).value(:integer, gteq?: 0)
            required(:frequency).value(:string, included_in?: FREQUENCY_FACTORS.keys)
          end
        end
      end

      # Each item's monthly amount, its type rule, and whether it counts, for the agent to explain
      # the total. person_income_counts and counts are nil while unknown.
      fact :income_item_details, per_entity: :months, allow_unmet_dependencies: true do
        dependency :income_items
        dependency :income_counts_by_member, from: :household
        dependency :is_child_or_tax_dependent_by_member, from: :household
        dependency :renewer_income_counts, from: :household
        dependency :renewer_is_child_or_tax_dependent, from: :household

        proc do
          deps = data[:dependencies]
          next deps[:income_items] if unknown?(deps[:income_items])

          deps[:income_items].map do |item|
            member = item[:household_member]
            person_counts = member.nil? ? IncomeFacts.known_or_nil(deps[:renewer_income_counts]) : IncomeFacts.known_or_nil(deps[:income_counts_by_member], member)
            child_or_dependent = member.nil? ? IncomeFacts.known_or_nil(deps[:renewer_is_child_or_tax_dependent]) : IncomeFacts.known_or_nil(deps[:is_child_or_tax_dependent_by_member], member)
            type_counts = case INCOME_TYPES.fetch(item[:type])
            in :counted then true
            in :excluded then false
            in :counted_unless_child_or_tax_dependent then child_or_dependent.nil? ? nil : !child_or_dependent
            end
            counts = (type_counts == false || person_counts == false) ? false : (type_counts && person_counts)

            {
              household_member: member,
              type: item[:type],
              monthly_cents: (item[:amount_cents] * FREQUENCY_FACTORS.fetch(item[:frequency])).round,
              type_counts:,
              person_income_counts: person_counts,
              counts:
            }
          end
        end
      end

      # Unknown until we know whether every item counts; the unknown names only the people whose
      # status is still needed.
      fact :countable_income_cents, per_entity: :months, allow_unmet_dependencies: true do
        dependency :income_item_details
        dependency :income_counts_by_member, from: :household
        dependency :is_child_or_tax_dependent_by_member, from: :household
        dependency :renewer_income_counts, from: :household
        dependency :renewer_is_child_or_tax_dependent, from: :household

        proc do
          deps = data[:dependencies]
          details = deps[:income_item_details]
          next details if unknown?(details)

          unknowns = details.select { _1[:counts].nil? }.flat_map { IncomeFacts.unknowns_for_item(_1, deps) }
          next merge_unknowns(unknowns) if unknowns.any?

          details.select { _1[:counts] }.sum { _1[:monthly_cents] }
        end
      end
    end

    in_module :income do
      # Income for the renewal month: a point-in-time estimate (WAC 182-509-0310).
      fact :renewal_month_countable_income_cents, allow_unmet_dependencies: true do
        input :months do
          required(:months).array(:hash)
        end
        dependency :renewal_month, from: :renewer
        dependency :month, from: :months
        dependency :countable_income_cents, from: :months

        proc do
          next data_errors unless data[:input][:months].is_a?(Array)

          renewal_month = data[:dependencies][:renewal_month]
          next renewal_month if unknown?(renewal_month)

          id = data[:dependencies][:month].key(renewal_month)
          next FactGraph::Error.new(fact_bad_inputs: {[:months] => Set["needs an entry for the renewal month"]}, fact_dependency_unmet: {}) if id.nil?

          data[:dependencies][:countable_income_cents].fetch(id) { unknown_entity(:months, :countable_income_cents, id) }
        end
      end

      # HCA's chart lists sizes 1 to 10, plus an amount for each person over 10.
      %w[adult family].each do |program|
        fact :"#{program}_income_limit_cents" do
          dependency :size, from: :household
          dependency :"#{program}_income_limit_cents_by_household_size", from: :standards
          dependency :"#{program}_income_limit_cents_each_additional_person", from: :standards

          proc do
            deps = data[:dependencies]
            table = deps[:"#{program}_income_limit_cents_by_household_size"]
            size = deps[:size]
            next table[size - 1] if size <= table.size

            table.last + (size - table.size) * deps[:"#{program}_income_limit_cents_each_additional_person"]
          end
        end
      end

      fact :meets_income_limit do
        dependency :renewal_month_countable_income_cents
        dependency :adult_income_limit_cents
        proc { data[:dependencies][:renewal_month_countable_income_cents] <= data[:dependencies][:adult_income_limit_cents] }
      end

      fact :income_over_limit_by_cents do
        dependency :renewal_month_countable_income_cents
        dependency :adult_income_limit_cents
        proc { [data[:dependencies][:renewal_month_countable_income_cents] - data[:dependencies][:adult_income_limit_cents], 0].max }
      end

      fact :meets_family_income_limit do
        dependency :renewal_month_countable_income_cents
        dependency :family_income_limit_cents
        proc { data[:dependencies][:renewal_month_countable_income_cents] <= data[:dependencies][:family_income_limit_cents] }
      end
    end
  end
end

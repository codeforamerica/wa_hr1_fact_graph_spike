# frozen_string_literal: true

# Who is in the renewer's household (their "medical assistance unit"), how big it is, and whose
# income counts. WAC 182-506-0010 and 182-506-0012 for membership, WAC 182-509-0360 for income.
#
# Household members are described relative to the renewer. The list includes anyone the rules
# could pull in, even if they don't live with the renewer: a parent who claims the renewer as a tax
# dependent is in the household wherever they live.
module HouseholdFacts
  extend ActiveSupport::Concern

  RELATIONSHIPS = %w[spouse child parent sibling other_relative not_related].freeze

  included do
    # Which of the WAC 182-506-0012 rules applies to the renewer.
    in_module :household do
      all_of_fact :renewer_uses_tax_filer_rules,
        dep(:expects_to_file_taxes, from: :renewer),
        no(:expects_to_be_claimed_as_dependent, from: :renewer)

      # A tax dependent is treated as a nonfiler if one of these applies (WAC 182-506-0012(2)(b)(ii)).
      # The renewer can't be the claimer's spouse, so "neither the spouse nor the child of the tax
      # filer" means not claimed by a parent.
      any_of_fact :renewer_meets_tax_dependent_exception,
        no(:claimed_by_parent, from: :renewer),
        dep(:claimed_by_noncustodial_parent, from: :renewer),
        :renewer_under_19_with_parents_filing_separately

      all_of_fact :renewer_under_19_with_parents_filing_separately,
        dep(:under_19, from: :renewer),
        dep(:lives_with_both_parents, from: :renewer),
        no(:parents_file_jointly, from: :renewer)

      all_of_fact :renewer_uses_tax_dependent_rules,
        dep(:expects_to_be_claimed_as_dependent, from: :renewer),
        no(:renewer_meets_tax_dependent_exception)

      any_of_fact :renewer_uses_nonfiler_rules,
        :renewer_is_nonfiler,
        :renewer_is_tax_dependent_treated_as_nonfiler

      all_of_fact :renewer_is_nonfiler,
        no(:expects_to_file_taxes, from: :renewer),
        no(:expects_to_be_claimed_as_dependent, from: :renewer)

      all_of_fact :renewer_is_tax_dependent_treated_as_nonfiler,
        dep(:expects_to_be_claimed_as_dependent, from: :renewer),
        :renewer_meets_tax_dependent_exception

      # A nonfiler under 19 also has their parents and young siblings in their household.
      all_of_fact :renewer_is_nonfiler_under_19,
        :renewer_uses_nonfiler_rules,
        dep(:under_19, from: :renewer)

      # Someone in an institution for 30 days is the only person in their household (WAC 182-506-0010(3)).
      fact :others_can_be_in_household do
        dependency :in_medical_institution_30_days, from: :renewer
        proc { !data[:dependencies][:in_medical_institution_30_days] }
      end
    end

    in_module :household_members do
      # What the renewer tells us about each person
      fact :relationship_to_renewer, per_entity: :household_members do
        input :relationship_to_renewer, per_entity: true, value: :string, included_in?: RELATIONSHIPS
      end

      fact :lives_with_renewer, per_entity: :household_members do
        input :lives_with_renewer, per_entity: true, value: :bool?
      end

      fact :age, per_entity: :household_members do
        input :age, per_entity: true, value: :integer, gteq?: 0
      end

      fact :claimed_as_dependent_by_renewer, per_entity: :household_members do
        input :claimed_as_dependent_by_renewer, per_entity: true, value: :bool?
      end

      fact :claims_renewer_as_dependent, per_entity: :household_members do
        input :claims_renewer_as_dependent, per_entity: true, value: :bool?
      end

      # The spouse of whoever claims the renewer, when that spouse lives with them.
      fact :lives_with_renewers_claimer_as_spouse, per_entity: :household_members do
        input :lives_with_renewers_claimer_as_spouse, per_entity: true, value: :bool?
      end

      fact :claimed_by_renewers_claimer, per_entity: :household_members do
        input :claimed_by_renewers_claimer, per_entity: true, value: :bool?
      end

      fact :pregnant, per_entity: :household_members do
        input :pregnant, per_entity: true, value: :bool?
      end

      fact :expected_unborn_children, per_entity: :household_members do
        input :expected_unborn_children, per_entity: true, value: :integer, gteq?: 1
      end

      # A shortcut: the person tells us, rather than us encoding the IRS filing thresholds.
      fact :required_to_file_taxes, per_entity: :household_members do
        input :required_to_file_taxes, per_entity: true, value: :bool?
      end

      # Relationships
      %w[spouse child parent sibling].each do |relationship|
        fact :"is_#{relationship}", per_entity: :household_members do
          dependency :relationship_to_renewer
          proc { data[:dependencies][:relationship_to_renewer] == relationship }
        end
      end

      fact :under_19, per_entity: :household_members do
        dependency :age
        proc { data[:dependencies][:age] < 19 }
      end

      # Each way someone can be in the renewer's household
      all_of_fact :in_household_as_spouse, :is_spouse, :lives_with_renewer,
        per_entity: :household_members

      all_of_fact :in_household_as_renewers_tax_dependent,
        dep(:renewer_uses_tax_filer_rules, from: :household),
        :claimed_as_dependent_by_renewer,
        per_entity: :household_members

      all_of_fact :in_household_as_renewers_claimer,
        dep(:renewer_uses_tax_dependent_rules, from: :household),
        :claims_renewer_as_dependent,
        per_entity: :household_members

      all_of_fact :in_household_as_renewers_claimers_spouse,
        dep(:renewer_uses_tax_dependent_rules, from: :household),
        :lives_with_renewers_claimer_as_spouse,
        per_entity: :household_members

      # The claimer and the claimer's spouse can't be the claimer's tax dependents. Ruling them out
      # first means we never ask whether someone claims their own spouse.
      all_of_fact :in_household_as_renewers_claimers_tax_dependent,
        dep(:renewer_uses_tax_dependent_rules, from: :household),
        no(:claims_renewer_as_dependent),
        no(:lives_with_renewers_claimer_as_spouse),
        :claimed_by_renewers_claimer,
        per_entity: :household_members

      all_of_fact :in_household_as_nonfilers_child,
        dep(:renewer_uses_nonfiler_rules, from: :household),
        :is_child, :lives_with_renewer, :under_19,
        per_entity: :household_members

      all_of_fact :in_household_as_nonfilers_parent,
        dep(:renewer_is_nonfiler_under_19, from: :household),
        :is_parent, :lives_with_renewer,
        per_entity: :household_members

      all_of_fact :in_household_as_nonfilers_sibling,
        dep(:renewer_is_nonfiler_under_19, from: :household),
        :is_sibling, :lives_with_renewer, :under_19,
        per_entity: :household_members

      any_of_fact :meets_a_household_rule,
        :in_household_as_spouse,
        :in_household_as_renewers_tax_dependent,
        :in_household_as_renewers_claimer,
        :in_household_as_renewers_claimers_spouse,
        :in_household_as_renewers_claimers_tax_dependent,
        :in_household_as_nonfilers_child,
        :in_household_as_nonfilers_parent,
        :in_household_as_nonfilers_sibling,
        per_entity: :household_members

      all_of_fact :in_household,
        dep(:others_can_be_in_household, from: :household),
        :meets_a_household_rule,
        per_entity: :household_members

      # Unborn children count toward household size (WAC 182-506-0010(2)(b))
      fact :unborn_children_counted, per_entity: :household_members, allow_unmet_dependencies: true do
        dependency :in_household
        dependency :pregnant
        dependency :expected_unborn_children

        proc do
          data in dependencies: {in_household:, pregnant:, expected_unborn_children:}
          next 0 if in_household == false
          next in_household if unknown?(in_household)
          next 0 if pregnant == false
          next pregnant if unknown?(pregnant)

          expected_unborn_children
        end
      end

      # Whose income counts (WAC 182-509-0360): a child 18 or younger, or a tax dependent, only
      # counts if they're required to file taxes.
      any_of_fact :is_child_or_tax_dependent,
        :under_19,
        :in_household_as_renewers_tax_dependent,
        :in_household_as_renewers_claimers_tax_dependent,
        per_entity: :household_members

      any_of_fact :income_counts_if_in_household,
        no(:is_child_or_tax_dependent),
        :required_to_file_taxes,
        per_entity: :household_members

      all_of_fact :income_counts, :in_household, :income_counts_if_in_household,
        per_entity: :household_members
    end

    in_module :household do
      fact :renewer_unborn_children_counted, allow_unmet_dependencies: true do
        dependency :pregnant, from: :renewer
        dependency :expected_unborn_children, from: :renewer

        proc do
          data in dependencies: {pregnant:, expected_unborn_children:}
          next 0 if pregnant == false
          next pregnant if unknown?(pregnant)

          expected_unborn_children
        end
      end

      any_of_fact :renewer_is_child_or_tax_dependent,
        dep(:under_19, from: :renewer),
        dep(:expects_to_be_claimed_as_dependent, from: :renewer)

      any_of_fact :renewer_income_counts,
        no(:renewer_is_child_or_tax_dependent),
        dep(:required_to_file_taxes, from: :renewer)

      # Household size: the renewer, everyone else in the household, and unborn children.
      fact :size, allow_unmet_dependencies: true do
        input :household_members do
          required(:household_members).array(:hash)
        end
        dependency :in_household, from: :household_members
        dependency :unborn_children_counted, from: :household_members
        dependency :renewer_unborn_children_counted

        proc do
          next data_errors unless data[:input][:household_members].is_a?(Array)

          ids = (0...data[:input][:household_members].count).to_a
          members = every_entity(data[:dependencies][:in_household], entity_ids: ids, fact: [:household_members, :in_household])
          unborn = every_entity(data[:dependencies][:unborn_children_counted], entity_ids: ids, fact: [:household_members, :unborn_children_counted])
          renewer_unborn = data[:dependencies][:renewer_unborn_children_counted]
          unknowns = [members, unborn, renewer_unborn].select { unknown?(_1) }
          next merge_unknowns(unknowns) if unknowns.any?

          1 + members.values.count(true) + unborn.values.sum + renewer_unborn
        end
      end
    end
  end
end

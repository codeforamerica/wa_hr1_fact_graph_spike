# frozen_string_literal: true

# Whether the renewer is likely eligible for Apple Health for Adults (WAC 182-505-0250), combining the
# general requirements with the household, income, immigration, and work requirement modules.
module EligibilityFacts
  extend ActiveSupport::Concern

  included do
    in_module :renewer do
      # Lives in Washington (WAC 182-503-0520). We take the person's word rather than modeling intent
      # to reside or the rules for people in institutions (WAC 182-503-0525).
      fact :lives_in_washington do
        input [:renewer, :lives_in_washington], value: :bool?
      end

      # Has a Social Security number or has applied for one (WAC 182-503-0515). The WAC's exceptions
      # aren't modeled.
      fact :has_ssn_or_applied_for_one do
        input [:renewer, :has_ssn_or_applied_for_one], value: :bool?
      end

      # Eligible for and enrolled in SSI-related, foster care, or adoption support coverage, which come
      # before the adult program (WAC 182-505-0250(1)(c)).
      fact :enrolled_in_ssi_foster_care_or_adoption_support_coverage do
        input [:renewer, :enrolled_in_ssi_foster_care_or_adoption_support_coverage], value: :bool?
      end

      # A parent or caretaker relative of a dependent child (WAC 182-503-0565). They're considered for
      # family coverage first (WAC 182-505-0250(2)).
      fact :parent_or_caretaker_relative_of_dependent_child do
        input [:renewer, :parent_or_caretaker_relative_of_dependent_child], value: :bool?
      end
    end

    in_module :eligibility do
      fact :meets_age do
        dependency :age, from: :renewer
        proc { (19...65).cover?(data[:dependencies][:age]) }
      end

      fact :not_on_medicare do
        dependency :has_medicare, from: :renewer
        proc { !data[:dependencies][:has_medicare] }
      end

      fact :not_in_other_mandatory_coverage do
        dependency :enrolled_in_ssi_foster_care_or_adoption_support_coverage, from: :renewer
        proc { !data[:dependencies][:enrolled_in_ssi_foster_care_or_adoption_support_coverage] }
      end

      # A shortcut: we don't model family coverage, only flag when someone would be considered for it
      # first. Family coverage has no work requirement.
      all_of_fact :considered_for_family_coverage_first,
        dep(:parent_or_caretaker_relative_of_dependent_child, from: :renewer),
        dep(:meets_family_income_limit, from: :income)

      # Apple Health for Adults.
      all_of_fact :likely_eligible,
        :meets_age,
        :not_on_medicare,
        :not_in_other_mandatory_coverage,
        no(:considered_for_family_coverage_first),
        dep(:lives_in_washington, from: :renewer),
        dep(:has_ssn_or_applied_for_one, from: :renewer),
        dep(:meets_citizenship_or_immigration, from: :immigration),
        dep(:meets_income_limit, from: :income),
        dep(:meets_work_requirement, from: :work_requirement)

      # Approximates family coverage's other requirements with the adult program's.
      all_of_fact :likely_eligible_for_family_coverage_instead,
        :considered_for_family_coverage_first,
        dep(:lives_in_washington, from: :renewer),
        dep(:has_ssn_or_applied_for_one, from: :renewer),
        dep(:meets_citizenship_or_immigration, from: :immigration)
    end
  end
end

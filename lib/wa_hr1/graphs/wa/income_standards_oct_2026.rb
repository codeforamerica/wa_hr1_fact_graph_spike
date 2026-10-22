# frozen_string_literal: true

module FactGraphs
  module Wa
    # HCA's income standards chart effective October 1, 2026
    # (docs/resources/hca-income-standards-2026-10.txt). It's the latest chart published, so it
    # stands in for renewals in 2027 and 2028 until HCA publishes the next one.
    class IncomeStandardsOct2026 < FactGraphs::States::Wa
      in_module :standards do
        constant(:standards_effective) { "2026-10-01" }

        # "138% FPL - New Adult (N05)". The 5% disregard is already included. Index 0 is a
        # household of 1. The chart's "11-person+" column ($654) matches the step between
        # sizes, so we read it as the amount added for each person over 10.
        constant(:adult_income_limit_cents_by_household_size) do
          [183_500, 249_000, 314_200, 379_500, 444_900, 510_200, 575_500, 640_900, 706_100, 771_400]
        end
        constant(:adult_income_limit_cents_each_additional_person) { 65_400 }

        # "Family (N01)", for the family-coverage shortcut. The chart has N/A for 11+;
        # WAC 182-505-0100(2) gives the 10-person amount for 11+.
        constant(:family_income_limit_cents_by_household_size) do
          [51_100, 65_800, 82_000, 97_200, 112_700, 128_400, 147_100, 163_100, 179_200, 195_100]
        end
        constant(:family_income_limit_cents_each_additional_person) { 0 }
      end
    end
  end
end

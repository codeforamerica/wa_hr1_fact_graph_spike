# frozen_string_literal: true

module FactGraphs
  module States
    # Washington's choices, from HCA's August 2026 analysis of the federal rule
    # (docs/resources/hr1-work-requirements-ifr-summary-analysis.txt) and the WAC.
    class Wa < FactGraphs::Base
      in_module :standards do
        constant(:state_code) { "WA" }

        # Any one month in the 6 before renewal (HCA analysis; ADR-0002).
        constant(:renewal_lookback_months) { 6 }

        # HCA's credit-hour table, used as published: index 0 is 1 credit hour.
        # Credits outside the table (more than 6, or fractional) have no value yet.
        constant(:monthly_hours_by_credit_hours) { [13, 26, 39, 52, 66, 78] }

        # "Outside your community" means a commute of over an hour (HCA analysis).
        constant(:outside_community_commute_minutes) { 60 }
      end
    end
  end
end

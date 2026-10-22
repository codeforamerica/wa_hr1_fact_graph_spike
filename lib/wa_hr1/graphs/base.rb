# frozen_string_literal: true

module FactGraphs
  # Federal rules: H.R. 1 (P.L. 119-21) and the community engagement rule at 42 CFR 435.552.
  # Graphs are layered Base -> state (States::Wa) -> income standards period
  # (Wa::IncomeStandardsOct2026); only the last is evaluated.
  #
  # Values that cross the graph boundary must survive a JSON round trip: money is integer cents,
  # dates and months are ISO 8601 strings, and enums are strings.
  class Base < FactGraph::Graph
    extend WaHr1::Macros

    include RenewerFacts
    include HouseholdFacts

    in_module :standards do
      constant(:work_requirement_start_date) { "2027-01-01" }

      # The federal minimum wage times 80 hours, as stated in HCA's August 2026 analysis.
      constant(:min_monthly_income_cents) { 58_000 }
      constant(:min_monthly_hours) { 80 }

      # Used to work out hours from income when hours aren't known (42 CFR 435.552(e)(2)).
      constant(:federal_minimum_wage_cents) { 725 }

      # The seasonal-worker income test averages the preceding 6 months (42 CFR 435.552(g)).
      constant(:seasonal_worker_average_months) { 6 }
    end
  end
end

# frozen_string_literal: true

# Citizenship and immigration status for Apple Health for Adults, from October 1, 2026.
#
# H.R. 1 section 71109 narrowed "qualified noncitizen" to lawful permanent residents (LPRs),
# Cuban/Haitian entrants, and COFA migrants. WAC 182-503-0535 hasn't been updated for it yet, so this
# follows HCA's noncitizen fact sheet (docs/resources/hr1-noncitizen-fact-sheet.txt), and the WAC for
# the parts the fact sheet doesn't change: who counts as a citizen, and how the 5-year bar works.
module ImmigrationFacts
  extend ActiveSupport::Concern

  STATUSES = %w[
    us_citizen
    us_national
    qualifying_american_indian_born_abroad
    lawful_permanent_resident
    cuban_haitian_entrant
    cofa_migrant
    other_lawful_status
    undocumented
  ].freeze

  # Statuses that stay exempt from the 5-year bar after someone becomes an LPR (HCA fact sheet).
  FIVE_YEAR_BAR_EXEMPT_PRIOR_STATUSES = %w[
    refugee
    asylee
    amerasian
    cuban_haitian_entrant
    trafficking_victim
    iraqi_or_afghan_special_immigrant
  ].freeze

  FIVE_YEARS_IN_MONTHS = 60

  included do
    in_module :renewer do
      fact :immigration_status do
        input [:renewer, :immigration_status], value: :string, included_in?: STATUSES
      end

      # For LPRs: the date they became an LPR, like "2022-05-10".
      fact :became_lpr_on do
        input [:renewer, :became_lpr_on], value: :string, format?: /\A\d{4}-\d{2}-\d{2}\z/
      end

      # For LPRs: the status they had before, if it's one that stays exempt from the 5-year bar.
      fact :lpr_prior_status do
        input [:renewer, :lpr_prior_status], value: :string, included_in?: FIVE_YEAR_BAR_EXEMPT_PRIOR_STATUSES + ["none"]
      end

      # An active-duty service member or honorably discharged veteran, or their family.
      fact :armed_forces_connection do
        input [:renewer, :armed_forces_connection], value: :bool?
      end
    end

    in_module :immigration do
      {
        is_citizen_or_national: %w[us_citizen us_national qualifying_american_indian_born_abroad],
        is_lawful_permanent_resident: %w[lawful_permanent_resident],
        is_cuban_haitian_entrant: %w[cuban_haitian_entrant],
        is_cofa_migrant: %w[cofa_migrant]
      }.each do |name, statuses|
        fact name do
          dependency :immigration_status, from: :renewer
          proc { statuses.include?(data[:dependencies][:immigration_status]) }
        end
      end

      fact :five_years_since_becoming_lpr do
        dependency :became_lpr_on, from: :renewer
        dependency :renewal_month, from: :renewer
        proc { WaHr1::Months.index(data[:dependencies][:renewal_month]) - WaHr1::Months.index(data[:dependencies][:became_lpr_on]) >= FIVE_YEARS_IN_MONTHS }
      end

      fact :prior_status_exempt_from_five_year_bar do
        dependency :lpr_prior_status, from: :renewer
        proc { data[:dependencies][:lpr_prior_status] != "none" }
      end

      any_of_fact :meets_or_exempt_from_five_year_bar,
        :five_years_since_becoming_lpr,
        :prior_status_exempt_from_five_year_bar,
        dep(:armed_forces_connection, from: :renewer)

      gated_all_of_fact :qualifies_as_lpr, :is_lawful_permanent_resident, :meets_or_exempt_from_five_year_bar

      # Cuban/Haitian entrants are exempt from the 5-year bar, and COFA migrants aren't subject to it.
      any_of_fact :meets_citizenship_or_immigration,
        :is_citizen_or_national,
        :qualifies_as_lpr,
        :is_cuban_haitian_entrant,
        :is_cofa_migrant
    end
  end
end

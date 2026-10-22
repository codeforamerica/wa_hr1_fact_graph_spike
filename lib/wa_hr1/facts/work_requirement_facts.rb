# frozen_string_literal: true

# The community engagement ("work") requirement at renewal: 42 CFR 435.552 as Washington applies it
# (docs/resources/hr1-work-requirements-ifr-summary-analysis.txt).
#
# At renewal, a person meets it if, in any one of the 6 months before renewal, they had an exclusion,
# an exemption, or enough activity. Exclusions and exemptions are asked once, as "in any of those
# months"; activities are reported per month, because hours only combine within a month.
module WorkRequirementFacts
  extend ActiveSupport::Concern

  # Washington's "current month exclusions": one yes/no each, meaning "in any of the 6 months before
  # renewal". Pregnancy and age come from the renewer module.
  EXCLUSION_INPUTS = %i[
    is_american_indian_alaska_native
    is_former_foster_youth
    within_12_months_postpartum
    cares_for_child_under_14
    cares_for_person_with_disability
    is_veteran_with_total_disability
    is_medically_frail
    meets_snap_work_requirements
    complies_with_tanf_work_requirements
    in_drug_or_alcohol_treatment
    incarcerated_or_released_within_3_months
  ].freeze

  # Exemptions other than age and Medicare. The hardships: inpatient care and traveling over an hour
  # for medical care are ones a person asks for; a disaster declaration and high county unemployment
  # are applied automatically.
  EXEMPTION_INPUTS = %i[
    enrolled_in_other_apple_health_program
    hardship_inpatient_care
    hardship_travel_for_medical_care
    hardship_disaster_area
    hardship_high_unemployment_county
  ].freeze

  EARNED_INCOME_TYPES = %w[wages self_employment].freeze

  def self.month_index(month)
    year, month_number = month.split("-").map(&:to_i)
    year * 12 + month_number - 1
  end

  # The `count` months before `month`, oldest first.
  def self.months_before(month, count)
    index = month_index(month)
    count.downto(1).map { |back| (index - back).divmod(12).then { |year, m| format("%04d-%02d", year, m + 1) } }
  end

  included do
    in_module :work_requirement do
      (EXCLUSION_INPUTS + EXEMPTION_INPUTS + [:is_seasonal_worker]).each do |name|
        fact name do
          input [:work_requirement, name], value: :bool?
        end
      end

      fact :applies_to_renewal do
        dependency :renewal_month, from: :income
        dependency :first_renewal_month_with_work_requirement, from: :standards
        proc { data[:dependencies][:renewal_month] >= data[:dependencies][:first_renewal_month_with_work_requirement] }
      end

      fact :under_26 do
        dependency :age, from: :renewer
        proc { data[:dependencies][:age] < 26 }
      end

      all_of_fact :is_former_foster_youth_under_26, :is_former_foster_youth, :under_26

      any_of_fact :pregnant_or_postpartum, dep(:pregnant, from: :renewer), :within_12_months_postpartum

      any_of_fact :has_exclusion,
        :is_american_indian_alaska_native,
        :is_former_foster_youth_under_26,
        :pregnant_or_postpartum,
        *(EXCLUSION_INPUTS - %i[is_american_indian_alaska_native is_former_foster_youth within_12_months_postpartum])

      any_of_fact :has_exemption,
        dep(:under_19, from: :renewer),
        dep(:has_medicare, from: :renewer),
        *EXEMPTION_INPUTS
    end

    in_module :months do
      # Activities, reported per month
      %i[work_hours work_program_hours community_service_hours education_program_hours].each do |name|
        fact name, per_entity: :months do
          input name, per_entity: true, value: :integer, gteq?: 0
        end
      end

      # HCA's credit-hour table covers 1 to 6 credits. We only ask for credits when someone is
      # enrolled less than half-time, so more than 6 is likely a mistake; a resolver can't report an
      # error with the month's entity ID, so the input check does it.
      fact :credit_hours, per_entity: :months do
        input :credit_hours, per_entity: true, value: :integer, gteq?: 0, lteq?: 6
      end

      %i[doesnt_know_work_hours in_education_program enrolled_at_least_half_time school_uses_credit_hours].each do |name|
        fact name, per_entity: :months do
          input name, per_entity: true, value: :bool?
        end
      end

      fact :in_lookback_window, per_entity: :months do
        dependency :month
        dependency :renewal_month, from: :income
        dependency :renewal_lookback_months, from: :standards

        proc do
          data in dependencies: {month:, renewal_month:, renewal_lookback_months:}
          distance = WorkRequirementFacts.month_index(renewal_month) - WorkRequirementFacts.month_index(month)
          distance.between?(1, renewal_lookback_months)
        end
      end

      # Income path: countable household MAGI income of at least $580 (42 CFR 435.552(f)).
      fact :meets_income_minimum, per_entity: :months do
        dependency :countable_income_cents
        dependency :min_monthly_income_cents, from: :standards
        proc { data[:dependencies][:countable_income_cents] >= data[:dependencies][:min_monthly_income_cents] }
      end

      # Hours from income, when the person doesn't know their hours (42 CFR 435.552(e)(2)): the
      # renewer's own countable earned income divided by the federal minimum wage, rounded down.
      fact :work_hours_from_income, per_entity: :months do
        dependency :income_item_details
        dependency :federal_minimum_wage_cents, from: :standards

        proc do
          data in dependencies: {income_item_details:, federal_minimum_wage_cents:}
          earned = income_item_details.select { _1[:household_member].nil? && _1[:counts] && EARNED_INCOME_TYPES.include?(_1[:type]) }
          earned.sum { _1[:monthly_cents] } / federal_minimum_wage_cents
        end
      end

      fact :work_hours_counted, per_entity: :months, allow_unmet_dependencies: true do
        dependency :work_hours
        dependency :doesnt_know_work_hours
        dependency :work_hours_from_income

        proc do
          data in dependencies: {work_hours:, doesnt_know_work_hours:, work_hours_from_income:}
          next work_hours unless unknown?(work_hours)
          # Ask for hours first; only "I don't know" brings in hours from income.
          next work_hours unless doesnt_know_work_hours == true

          work_hours_from_income
        end
      end

      all_of_fact :enrolled_half_time_or_more, :in_education_program, :enrolled_at_least_half_time,
        per_entity: :months

      # Education hours, for combining with other activities when enrolled less than half-time
      # (42 CFR 435.552(d), (e)). Credit hours use HCA's table as published.
      fact :education_hours, per_entity: :months, allow_unmet_dependencies: true do
        dependency :in_education_program
        dependency :enrolled_at_least_half_time
        dependency :school_uses_credit_hours
        dependency :credit_hours
        dependency :education_program_hours
        dependency :monthly_hours_by_credit_hours, from: :standards

        proc do
          deps = data[:dependencies]
          next 0 if deps[:in_education_program] == false
          next deps[:in_education_program] if unknown?(deps[:in_education_program])
          # At least half-time meets the requirement on its own; hours aren't needed.
          next 0 if deps[:enrolled_at_least_half_time] == true
          next deps[:enrolled_at_least_half_time] if unknown?(deps[:enrolled_at_least_half_time])
          next deps[:school_uses_credit_hours] if unknown?(deps[:school_uses_credit_hours])
          next deps[:education_program_hours] unless deps[:school_uses_credit_hours]

          credits = deps[:credit_hours]
          next credits if unknown?(credits)
          next 0 if credits.zero?

          deps[:monthly_hours_by_credit_hours].fetch(credits - 1)
        end
      end

      fact :total_activity_hours, per_entity: :months do
        dependency :work_hours_counted
        dependency :work_program_hours
        dependency :community_service_hours
        dependency :education_hours
        proc { data[:dependencies].values.sum }
      end

      fact :meets_hours_minimum, per_entity: :months do
        dependency :total_activity_hours
        dependency :min_monthly_hours, from: :standards
        proc { data[:dependencies][:total_activity_hours] >= data[:dependencies][:min_monthly_hours] }
      end

      fact :hours_short_of_minimum, per_entity: :months do
        dependency :total_activity_hours
        dependency :min_monthly_hours, from: :standards
        proc { [data[:dependencies][:min_monthly_hours] - data[:dependencies][:total_activity_hours], 0].max }
      end

      any_of_fact :meets_activity_requirement, :meets_income_minimum, :enrolled_half_time_or_more, :meets_hours_minimum,
        per_entity: :months

      all_of_fact :meets_requirement_in_month, :in_lookback_window, :meets_activity_requirement,
        per_entity: :months
    end

    in_module :work_requirement do
      # The month strings that make up the lookback window, for checking that each was reported.
      fact :lookback_months do
        dependency :renewal_month, from: :income
        dependency :renewal_lookback_months, from: :standards

        proc do
          data in dependencies: {renewal_month:, renewal_lookback_months:}
          WorkRequirementFacts.months_before(renewal_month, renewal_lookback_months)
        end
      end

      fact :meets_activity_requirement_in_lookback, allow_unmet_dependencies: true do
        input :months do
          required(:months).array(:hash)
        end
        dependency :meets_requirement_in_month, from: :months
        dependency :month, from: :months
        dependency :lookback_months

        proc do
          next data_errors unless data[:input][:months].is_a?(Array)

          ids = (0...data[:input][:months].count).to_a
          result = any_entity(data[:dependencies][:meets_requirement_in_month], entity_ids: ids, fact: [:months, :meets_requirement_in_month])
          next result if result == true

          lookback = data[:dependencies][:lookback_months]
          next merge_unknowns([result, lookback].select { unknown?(_1) }) if unknown?(lookback)

          missing = lookback - data[:dependencies][:month].values
          next result if missing.empty?

          missing_months = FactGraph::Error.new(fact_bad_inputs: {[:months] => Set["needs #{missing.join(", ")}"]}, fact_dependency_unmet: {})
          merge_unknowns([result, missing_months].select { unknown?(_1) })
        end
      end

      # Seasonal workers meet the income path for a month if their average countable income over the
      # 6 months before it is at least $580 (42 CFR 435.552(g)). Since any one lookback month is
      # enough, this only adds something through income from 7 to 12 months before renewal. True if
      # any lookback month's average is enough.
      fact :seasonal_average_meets_income_minimum, allow_unmet_dependencies: true do
        dependency :lookback_months
        dependency :month, from: :months
        dependency :countable_income_cents, from: :months
        dependency :seasonal_worker_average_months, from: :standards
        dependency :min_monthly_income_cents, from: :standards

        proc do
          deps = data[:dependencies]
          next deps[:lookback_months] if unknown?(deps[:lookback_months])

          month_results = deps[:lookback_months].map do |lookback_month|
            prior = WorkRequirementFacts.months_before(lookback_month, deps[:seasonal_worker_average_months])
            missing = prior.reject { deps[:month].value?(_1) }
            next FactGraph::Error.new(fact_bad_inputs: {[:months] => Set["needs #{missing.join(", ")}"]}, fact_dependency_unmet: {}) if missing.any?

            incomes = prior.map { |m| deps[:month].key(m) }.map { |id| deps[:countable_income_cents].fetch(id) { unknown_entity(:months, :countable_income_cents, id) } }
            unknowns = incomes.select { unknown?(_1) }
            next merge_unknowns(unknowns) if unknowns.any?

            # Compare totals so no rounding is needed.
            incomes.sum >= deps[:min_monthly_income_cents] * incomes.size
          end
          any_of(month_results)
        end
      end

      all_of_fact :meets_seasonal_worker_income, :is_seasonal_worker, :seasonal_average_meets_income_minimum

      any_of_fact :meets_work_requirement,
        no(:applies_to_renewal),
        :has_exclusion,
        :has_exemption,
        :meets_activity_requirement_in_lookback,
        :meets_seasonal_worker_income
    end
  end
end

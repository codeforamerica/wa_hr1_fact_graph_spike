# frozen_string_literal: true

RSpec.describe WorkRequirementFacts do
  let(:results) { FactGraph::Evaluator.evaluate(input, graph_class: FactGraphs::Wa::IncomeStandardsOct2026) }
  let(:work_requirement) { results[:work_requirement] }

  def missing(module_name, fact_name) = WaHr1::Unknowns.missing_inputs(results, module_name, fact_name)

  RENEWAL_MONTH = "2027-03"
  LOOKBACK = %w[2026-09 2026-10 2026-11 2026-12 2027-01 2027-02].freeze

  let(:renewer) do
    {age: 30, expects_to_file_taxes: true, expects_to_be_claimed_as_dependent: false, pregnant: false,
     has_medicare: false, in_medical_institution_30_days: false, renewal_month: RENEWAL_MONTH}
  end

  # No exclusions, exemptions, or seasonal work, so activities decide.
  let(:no_exclusions_or_exemptions) do
    (WorkRequirementFacts::EXCLUSION_INPUTS + WorkRequirementFacts::EXEMPTION_INPUTS + [:is_seasonal_worker]).to_h { [_1, false] }
  end

  let(:no_activity) do
    {work_hours: 0, work_program_hours: 0, community_service_hours: 0, in_education_program: false, income_items: []}
  end

  # The 6 lookback months with no activity, with `changes` merged into the most recent one, plus the
  # renewal month.
  def months(changes = {}, all: {})
    lookback = LOOKBACK.map { |m| no_activity.merge(all).merge(month: m) }
    lookback[-1] = lookback[-1].merge(changes)
    lookback + [{month: RENEWAL_MONTH, income_items: []}]
  end

  # Keywords other than these options are changes to the most recent lookback month.
  def build(members: [], all: {}, renewer_changes: {}, work_requirement: no_exclusions_or_exemptions, **month_changes)
    {renewer: renewer.merge(renewer_changes), household_members: members, work_requirement:, months: months(month_changes, all:)}
  end

  def wages(cents, member: nil) = {type: "wages", amount_cents: cents, frequency: "monthly", household_member: member}.compact

  describe "HCA's worked examples" do
    context "Mark and Gene: married, $200 Social Security plus $400 wages" do
      let(:input) do
        build(income_items: [{type: "social_security", amount_cents: 20_000, frequency: "monthly"}, wages(40_000, member: 0)],
          members: [{relationship_to_renewer: "spouse", lives_with_renewer: true, age: 40, pregnant: false}])
      end

      it "meets it on household income of $600" do
        expect(results[:months][:meets_income_minimum][5]).to be true
        expect(work_requirement[:meets_work_requirement]).to be true
      end
    end

    context "Steve: self-employed, $200 a month for 150 hours" do
      let(:input) { build(income_items: [{type: "self_employment", amount_cents: 20_000, frequency: "monthly"}], work_hours: 150) }

      it "meets it on hours" do
        expect(results[:months][:meets_income_minimum][5]).to be false
        expect(results[:months][:meets_hours_minimum][5]).to be true
        expect(work_requirement[:meets_work_requirement]).to be true
      end
    end

    context "Mary: 87 hours of in-kind work for reduced rent" do
      let(:input) { build(work_hours: 87) }

      it("meets it on hours") { expect(work_requirement[:meets_work_requirement]).to be true }
    end

    context "Fred: a 2-credit class and 60 hours with the Forest Service" do
      let(:input) do
        build(in_education_program: true, enrolled_at_least_half_time: false, school_uses_credit_hours: true,
          credit_hours: 2, community_service_hours: 60)
      end

      it "meets it on 86 combined hours" do
        expect(results[:months][:education_hours][5]).to eq 26
        expect(results[:months][:total_activity_hours][5]).to eq 86
        expect(work_requirement[:meets_work_requirement]).to be true
      end
    end

    context "Merv: welding school, 28 hours a month, no credits" do
      let(:input) do
        build(in_education_program: true, enrolled_at_least_half_time: false, school_uses_credit_hours: false,
          education_program_hours: 28)
      end

      it "doesn't meet it, and is 52 hours short that month" do
        expect(results[:months][:hours_short_of_minimum][5]).to eq 52
        expect(work_requirement[:meets_work_requirement]).to be false
      end
    end
  end

  describe "Maya" do
    context "enrolled half-time in one month" do
      let(:input) { build(in_education_program: true, enrolled_at_least_half_time: true) }

      it("meets it through school alone") { expect(work_requirement[:meets_work_requirement]).to be true }
    end

    context "less than half-time (3 credits) with 45 hours of work study" do
      let(:input) do
        build(in_education_program: true, enrolled_at_least_half_time: false, school_uses_credit_hours: true,
          credit_hours: 3, work_hours: 45, income_items: [{type: "work_study", amount_cents: 40_000, frequency: "monthly"}])
      end

      it "meets it on hours, even though work study doesn't count as income" do
        expect(results[:months][:countable_income_cents][5]).to eq 0
        expect(results[:months][:total_activity_hours][5]).to eq 84
        expect(work_requirement[:meets_work_requirement]).to be true
      end
    end
  end

  describe "hours from income" do
    let(:input) { build(work_hours: nil, doesnt_know_work_hours: true, community_service_hours: 15, income_items: [wages(50_000)]) }

    it "works out hours from earned income ÷ $7.25 when the person doesn't know their hours" do
      expect(results[:months][:work_hours_counted][5]).to eq 68
      expect(work_requirement[:meets_work_requirement]).to be true
    end

    it "asks for hours before using income" do
      results = FactGraph::Evaluator.evaluate(build(work_hours: nil, income_items: [wages(50_000)]), graph_class: FactGraphs::Wa::IncomeStandardsOct2026)
      expect(WaHr1::Unknowns.missing_inputs(results, :months, :work_hours_counted, entity_id: 5)).to eq Set[[:months, 5, :work_hours]]
    end
  end

  describe "seasonal workers" do
    # Income from a season 7 to 12 months before renewal (2026-03 to 2026-08), and nothing during
    # the lookback months themselves.
    def seasonal(*season_cents, seasonal_worker: true)
      earlier = %w[2026-03 2026-04 2026-05 2026-06 2026-07 2026-08].each_with_index.map do |m, i|
        {month: m, income_items: season_cents[i] ? [wages(season_cents[i])] : []}
      end
      input = build(work_requirement: no_exclusions_or_exemptions.merge(is_seasonal_worker: seasonal_worker))
      input[:months] = earlier + input[:months]
      FactGraph::Evaluator.evaluate(input, graph_class: FactGraphs::Wa::IncomeStandardsOct2026)[:work_requirement]
    end

    it "meets it when the 6 months before a lookback month average at least $580" do
      expect(seasonal(100_000, 100_000, 100_000, 100_000)[:meets_work_requirement]).to be true
    end

    it "doesn't when that average is under $580" do
      expect(seasonal(100_000, 100_000)[:meets_work_requirement]).to be false
    end

    it "doesn't count earlier income for someone who isn't a seasonal worker" do
      expect(seasonal(100_000, 100_000, 100_000, 100_000, seasonal_worker: false)[:meets_work_requirement]).to be false
    end
  end

  describe "exclusions, exemptions, and timing" do
    context "medically frail" do
      let(:input) { {renewer:, work_requirement: {is_medically_frail: true}} }

      it("meets it without asking about anything else") { expect(work_requirement[:meets_work_requirement]).to be true }
    end

    context "a former foster youth" do
      let(:input) { build(renewer_changes: {age: 24}, work_requirement: no_exclusions_or_exemptions.merge(is_former_foster_youth: true)) }

      it("is excluded under 26") { expect(work_requirement[:has_exclusion]).to be true }
    end

    context "renewing before February 2027" do
      let(:input) { {renewer: renewer.merge(renewal_month: "2027-01")} }

      it("doesn't have a work requirement yet") { expect(work_requirement[:meets_work_requirement]).to be true }
    end

    context "renewing in February 2027" do
      let(:input) { {renewer: renewer.merge(renewal_month: "2027-02"), work_requirement: no_exclusions_or_exemptions} }

      it("has one") { expect(work_requirement[:applies_to_renewal]).to be true }
    end
  end

  describe "asking only what matters" do
    context "when only some lookback months are reported" do
      let(:input) do
        build.tap { _1[:months] = _1[:months].drop(3) }
      end

      it "asks for the missing months rather than deciding no" do
        expect(work_requirement[:meets_work_requirement]).to unknown
        expect(missing(:work_requirement, :meets_work_requirement)).to eq Set[[:months]]
      end
    end

    context "when a month isn't in school" do
      let(:input) { build(work_hours: nil) }

      it "doesn't ask about enrollment or credits for it" do
        paths = missing(:months, :meets_requirement_in_month)
        expect(paths).to include([:months, 5, :work_hours])
        expect(paths.map(&:last)).not_to include(:enrolled_at_least_half_time, :credit_hours, :school_uses_credit_hours)
      end
    end
  end
end

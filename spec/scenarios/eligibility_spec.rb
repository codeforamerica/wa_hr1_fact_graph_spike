# frozen_string_literal: true

# End-to-end: whether a renewer is likely eligible for Apple Health for Adults.
RSpec.describe "Likely eligibility" do
  LOOKBACK_MONTHS = %w[2026-09 2026-10 2026-11 2026-12 2027-01 2027-02].freeze

  def evaluate(input) = FactGraph::Evaluator.evaluate(WaHr1::Input.with_sections(input), graph_class: FactGraphs::Wa::IncomeStandardsOct2026)

  def missing(results, module_name, fact_name) = WaHr1::Unknowns.missing_inputs(results, module_name, fact_name)

  let(:eligible_adult) do
    {age: 30, renewal_month: "2027-03", has_medicare: false, lives_in_washington: true, has_ssn_or_applied_for_one: true,
     enrolled_in_ssi_foster_care_or_adoption_support_coverage: false, parent_or_caretaker_relative_of_dependent_child: false,
     immigration_status: "us_citizen", expects_to_file_taxes: true, expects_to_be_claimed_as_dependent: false,
     pregnant: false, in_medical_institution_30_days: false}
  end

  let(:no_exclusions_or_exemptions) do
    (WorkRequirementFacts::EXCLUSION_INPUTS + WorkRequirementFacts::EXEMPTION_INPUTS + [:is_seasonal_worker]).to_h { [_1, false] }
  end

  # Six lookback months; the most recent one is in school half-time. Then the renewal month's income.
  def months(renewal_month_cents)
    lookback = LOOKBACK_MONTHS.map do |m|
      {month: m, income_items: [], work_hours: 0, work_program_hours: 0, community_service_hours: 0, in_education_program: false}
    end
    lookback[-1] = lookback[-1].merge(in_education_program: true, enrolled_at_least_half_time: true)
    lookback + [{month: "2027-03", income_items: [{type: "wages", amount_cents: renewal_month_cents, frequency: "monthly"}]}]
  end

  def wages(cents, member) = {type: "wages", amount_cents: cents, frequency: "monthly", household_member: member}

  it "is likely eligible when everything is met" do
    results = evaluate(renewer: eligible_adult, household_members: [], work_requirement: no_exclusions_or_exemptions, months: months(150_000))
    expect(results[:eligibility][:likely_eligible]).to be true
  end

  describe "Maya, a graduate student claimed by her parents" do
    let(:results) do
      maya = eligible_adult.merge(age: 24, expects_to_be_claimed_as_dependent: true, claimed_by_parent: true,
        claimed_by_noncustodial_parent: false, required_to_file_taxes: false)
      parents = [
        {relationship_to_renewer: "parent", lives_with_renewer: false, claims_renewer_as_dependent: true, age: 55, pregnant: false},
        {relationship_to_renewer: "parent", lives_with_renewer: false, claims_renewer_as_dependent: false,
         lives_with_renewers_claimer_as_spouse: true, age: 56, pregnant: false}
      ]
      input_months = months(40_000)
      input_months[-1][:income_items] += [wages(500_000, 0), wages(250_000, 1)]
      evaluate(renewer: maya, household_members: parents, work_requirement: no_exclusions_or_exemptions, months: input_months)
    end

    it "meets the work requirement through school, but isn't likely eligible because of her parents' income" do
      expect(results[:work_requirement][:meets_work_requirement]).to be true
      expect(results[:income][:meets_income_limit]).to be false
      expect(results[:income][:income_over_limit_by_cents]).to eq 750_000 - 314_200
      expect(results[:eligibility][:likely_eligible]).to be false
    end
  end

  describe "a parent with very low income" do
    let(:results) do
      parent = eligible_adult.merge(parent_or_caretaker_relative_of_dependent_child: true)
      child = [{relationship_to_renewer: "child", lives_with_renewer: true, age: 8, claimed_as_dependent_by_renewer: true,
                pregnant: false, required_to_file_taxes: false}]
      evaluate(renewer: parent, household_members: child, work_requirement: {}, months: months(50_000))
    end

    it "is pointed to family coverage, which has no work requirement, without being asked about it" do
      expect(results[:eligibility][:likely_eligible_for_family_coverage_instead]).to be true
      expect(results[:eligibility][:likely_eligible]).to be false
      expect(missing(results, :eligibility, :likely_eligible)).to be_empty
    end
  end

  it "isn't likely eligible at 65, without asking anything else" do
    results = evaluate(renewer: {age: 65, renewal_month: "2027-03"})
    expect(results[:eligibility][:likely_eligible]).to be false
    expect(missing(results, :eligibility, :likely_eligible)).to be_empty
  end

  it "asks for the basics when it knows almost nothing" do
    results = evaluate(renewer: {renewal_month: "2027-03"})
    expect(missing(results, :eligibility, :likely_eligible)).to include(
      [:renewer, :age], [:renewer, :immigration_status], [:renewer, :lives_in_washington],
      [:household_members], [:months], [:work_requirement, :is_medically_frail]
    )
  end
end

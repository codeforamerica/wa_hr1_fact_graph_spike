# frozen_string_literal: true

RSpec.describe IncomeFacts do
  let(:results) { FactGraph::Evaluator.evaluate(input, graph_class: FactGraphs::Wa::IncomeStandardsOct2026) }
  let(:income) { results[:income] }

  def missing(module_name, fact_name) = WaHr1::Unknowns.missing_inputs(results, module_name, fact_name)

  let(:independent_filer) do
    {age: 30, expects_to_file_taxes: true, expects_to_be_claimed_as_dependent: false, pregnant: false,
     in_medical_institution_30_days: false, renewal_month: "2027-03"}
  end

  def renewal_month_items(*items) = [{month: "2027-03", income_items: items}]

  def wages(cents, frequency = "monthly", member: nil)
    {type: "wages", amount_cents: cents, frequency:, household_member: member}.compact
  end

  describe "the income limit for one person ($1,835)" do
    let(:input) { {renewer: independent_filer, household_members: [], months: renewal_month_items(wages(monthly))} }

    context "at the limit" do
      let(:monthly) { 183_500 }

      it("meets it") { expect(income[:meets_income_limit]).to be true }
    end

    context "one dollar over" do
      let(:monthly) { 183_600 }

      it "doesn't meet it, and says by how much" do
        expect(income[:meets_income_limit]).to be false
        expect(income[:income_over_limit_by_cents]).to eq 100
      end
    end
  end

  describe "pay frequency (WAC 182-509-0310)" do
    {
      ["weekly", 40_000] => 172_000,
      ["every_two_weeks", 85_000] => 182_750,
      ["twice_monthly", 90_000] => 180_000,
      ["yearly", 1_200_000] => 100_000,
      ["one_time", 50_000] => 50_000
    }.each do |(frequency, cents), monthly|
      it "converts #{frequency} #{cents} cents to #{monthly} a month" do
        results = FactGraph::Evaluator.evaluate(
          {renewer: independent_filer, household_members: [], months: renewal_month_items(wages(cents, frequency))},
          graph_class: FactGraphs::Wa::IncomeStandardsOct2026
        )
        expect(results[:income][:renewal_month_countable_income_cents]).to eq monthly
      end
    end
  end

  describe "which kinds of income count" do
    let(:input) do
      {
        renewer: independent_filer,
        household_members: [],
        months: renewal_month_items(
          wages(100_000),
          {type: "work_study", amount_cents: 40_000, frequency: "monthly"},
          {type: "educational_benefit_for_education_expenses", amount_cents: 50_000, frequency: "monthly"},
          {type: "scholarship_for_living_expenses", amount_cents: 30_000, frequency: "monthly"},
          {type: "child_support_received", amount_cents: 20_000, frequency: "monthly"}
        )
      }
    end

    it "excludes work study, education benefits used for school, and child support" do
      expect(income[:renewal_month_countable_income_cents]).to eq 130_000
    end

    it "shows each item's treatment so the agent can explain the total" do
      details = results[:months][:income_item_details][0]
      expect(details.map { _1.slice(:type, :counts) }).to eq [
        {type: "wages", counts: true},
        {type: "work_study", counts: false},
        {type: "educational_benefit_for_education_expenses", counts: false},
        {type: "scholarship_for_living_expenses", counts: true},
        {type: "child_support_received", counts: false}
      ]
    end
  end

  describe "Social Security" do
    let(:input) do
      {
        renewer: independent_filer,
        household_members: [
          {relationship_to_renewer: "child", lives_with_renewer: true, age: 10, claimed_as_dependent_by_renewer: true,
           pregnant: false, required_to_file_taxes: true}
        ],
        months: renewal_month_items(
          {type: "social_security", amount_cents: 90_000, frequency: "monthly"},
          {type: "social_security", amount_cents: 40_000, frequency: "monthly", household_member: 0}
        )
      }
    end

    it "counts the renewer's own benefits, but not a dependent child's (WAC 182-509-0360(1))" do
      expect(income[:renewal_month_countable_income_cents]).to eq 90_000
    end
  end

  describe "Maya, claimed by her parents" do
    let(:input) do
      {
        renewer: {age: 24, expects_to_file_taxes: true, expects_to_be_claimed_as_dependent: true, claimed_by_parent: true,
                  claimed_by_noncustodial_parent: false, pregnant: false, in_medical_institution_30_days: false,
                  required_to_file_taxes: false, renewal_month: "2027-03"},
        household_members: [
          {relationship_to_renewer: "parent", lives_with_renewer: false, claims_renewer_as_dependent: true, age: 55, pregnant: false},
          {relationship_to_renewer: "parent", lives_with_renewer: false, claims_renewer_as_dependent: false,
           lives_with_renewers_claimer_as_spouse: true, age: 56, pregnant: false}
        ],
        months: renewal_month_items(wages(40_000), wages(500_000, member: 0), wages(250_000, member: 1))
      }
    end

    it "counts her parents' income but not hers, and compares it to the limit for 3" do
      expect(results[:household][:size]).to eq 3
      expect(income[:renewal_month_countable_income_cents]).to eq 750_000
      expect(income[:adult_income_limit_cents]).to eq 314_200
      expect(income[:meets_income_limit]).to be false
    end
  end

  describe "asking only what matters" do
    let(:input) do
      {
        renewer: independent_filer,
        household_members: [
          {relationship_to_renewer: "child", lives_with_renewer: true, age: 17, pregnant: false},
          {relationship_to_renewer: "child", lives_with_renewer: true, age: 15, pregnant: false}
        ],
        months: renewal_month_items(wages(100_000), wages(30_000, member: 1))
      }
    end

    it "asks about only the child who has income" do
      expect(missing(:income, :renewal_month_countable_income_cents)).to contain_exactly(
        [:household_members, 1, :claimed_as_dependent_by_renewer],
        [:household_members, 1, :required_to_file_taxes]
      )
    end

    it "asks for the renewal month's income when it's missing" do
      results = FactGraph::Evaluator.evaluate(
        {renewer: independent_filer, household_members: [], months: [{month: "2027-02", income_items: []}]},
        graph_class: FactGraphs::Wa::IncomeStandardsOct2026
      )
      expect(WaHr1::Unknowns.missing_inputs(results, :income, :meets_income_limit)).to include([:months])
    end

    it "flags an income item for someone who isn't in the household list" do
      results = FactGraph::Evaluator.evaluate(
        {renewer: independent_filer, household_members: [], months: renewal_month_items(wages(10_000, member: 3))},
        graph_class: FactGraphs::Wa::IncomeStandardsOct2026
      )
      expect(WaHr1::Unknowns.missing_inputs(results, :income, :renewal_month_countable_income_cents)).to eq Set[[:household_members]]
    end
  end
end

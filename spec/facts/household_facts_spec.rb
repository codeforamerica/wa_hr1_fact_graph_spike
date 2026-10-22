# frozen_string_literal: true

RSpec.describe HouseholdFacts do
  let(:results) { FactGraph::Evaluator.evaluate(input, graph_class: FactGraphs::Wa::IncomeStandardsOct2026) }
  let(:household) { results[:household] }
  let(:members) { results[:household_members] }

  def missing(module_name, fact_name) = WaHr1::Unknowns.missing_inputs(results, module_name, fact_name)

  # An adult who files their own taxes and isn't claimed by anyone.
  let(:independent_filer) do
    {age: 30, expects_to_file_taxes: true, expects_to_be_claimed_as_dependent: false,
     pregnant: false, in_medical_institution_30_days: false}
  end

  context "when the renewer files taxes and isn't claimed (tax filer rules)" do
    let(:input) do
      {
        renewer: independent_filer,
        household_members: [
          {relationship_to_renewer: "spouse", lives_with_renewer: true, age: 31, pregnant: true, expected_unborn_children: 1},
          {relationship_to_renewer: "child", lives_with_renewer: true, age: 4, claimed_as_dependent_by_renewer: true, pregnant: false},
          {relationship_to_renewer: "not_related", lives_with_renewer: true, age: 35, claimed_as_dependent_by_renewer: false}
        ]
      }
    end

    it "includes their spouse and the people they claim, but not a roommate" do
      expect(members[:in_household]).to eq({0 => true, 1 => true, 2 => false})
    end

    it "counts an unborn child toward household size" do
      expect(household[:size]).to eq 4
    end

    it "doesn't need to know whether a roommate is pregnant" do
      expect(missing(:household, :size)).to be_empty
    end
  end

  context "when the renewer is claimed by a parent (tax dependent rules): Maya" do
    let(:input) do
      {
        renewer: {age: 24, expects_to_file_taxes: true, expects_to_be_claimed_as_dependent: true,
                  claimed_by_parent: true, claimed_by_noncustodial_parent: false,
                  pregnant: false, in_medical_institution_30_days: false, required_to_file_taxes: false},
        household_members: [
          {relationship_to_renewer: "parent", lives_with_renewer: false, claims_renewer_as_dependent: true, age: 55, pregnant: false},
          {relationship_to_renewer: "parent", lives_with_renewer: false, claims_renewer_as_dependent: false,
           lives_with_renewers_claimer_as_spouse: true, age: 56, pregnant: false},
          {relationship_to_renewer: "sibling", lives_with_renewer: false, claims_renewer_as_dependent: false,
           lives_with_renewers_claimer_as_spouse: false, claimed_by_renewers_claimer: true, age: 16, pregnant: false,
           required_to_file_taxes: false}
        ]
      }
    end

    it "includes the parent who claims her, that parent's spouse, and the other people they claim, wherever they live" do
      expect(household[:renewer_uses_tax_dependent_rules]).to be true
      expect(members[:in_household]).to eq({0 => true, 1 => true, 2 => true})
      expect(household[:size]).to eq 4
    end

    it "counts her parents' income, but not hers or her sibling's, since neither is required to file" do
      expect(members[:income_counts]).to eq({0 => true, 1 => true, 2 => false})
      expect(household[:renewer_income_counts]).to be false
    end

    it "doesn't ask whether her mom claims her dad" do
      expect(missing(:household_members, :income_counts)).to be_empty
    end
  end

  context "when the renewer is claimed by someone other than a parent" do
    let(:input) do
      {
        renewer: {age: 22, expects_to_file_taxes: false, expects_to_be_claimed_as_dependent: true,
                  claimed_by_parent: false, pregnant: false, in_medical_institution_30_days: false},
        household_members: [
          {relationship_to_renewer: "other_relative", lives_with_renewer: true, claims_renewer_as_dependent: true, age: 70}
        ]
      }
    end

    it "uses the nonfiler rules, so the grandparent who claims them isn't in their household" do
      expect(household[:renewer_uses_nonfiler_rules]).to be true
      expect(members[:in_household]).to eq({0 => false})
      expect(household[:size]).to eq 1
    end
  end

  context "when the renewer doesn't file and isn't claimed (nonfiler rules)" do
    let(:input) do
      {
        renewer: {age: 40, expects_to_file_taxes: false, expects_to_be_claimed_as_dependent: false,
                  pregnant: false, in_medical_institution_30_days: false},
        household_members: [
          {relationship_to_renewer: "child", lives_with_renewer: true, age: 12, pregnant: false, required_to_file_taxes: false},
          {relationship_to_renewer: "child", lives_with_renewer: true, age: 20},
          {relationship_to_renewer: "parent", lives_with_renewer: true, age: 65}
        ]
      }
    end

    it "includes children under 19 who live with them, but not adult children or parents" do
      expect(members[:in_household]).to eq({0 => true, 1 => false, 2 => false})
      expect(household[:size]).to eq 2
    end

    it "doesn't count the young child's income, since they're not required to file" do
      expect(members[:income_counts]).to eq({0 => false, 1 => false, 2 => false})
    end
  end

  context "when the renewer has been in a medical institution for 30 days" do
    let(:input) do
      {
        renewer: independent_filer.merge(in_medical_institution_30_days: true),
        household_members: [{relationship_to_renewer: "spouse", lives_with_renewer: true}]
      }
    end

    it "makes them the only person in their household" do
      expect(household[:size]).to eq 1
    end
  end

  describe "asking only what matters" do
    let(:input) do
      {
        renewer: {age: 30, expects_to_file_taxes: true, expects_to_be_claimed_as_dependent: false},
        household_members: [{relationship_to_renewer: "child", lives_with_renewer: true, age: 3}]
      }
    end

    it "asks only for what household size still depends on" do
      expect(missing(:household, :size)).to contain_exactly(
        [:renewer, :in_medical_institution_30_days],
        [:renewer, :pregnant],
        [:household_members, 0, :claimed_as_dependent_by_renewer]
      )
    end

    it "never asks an adult renewer about their parents' tax filing" do
      paths = missing(:household, :size)
      expect(paths).not_to include([:renewer, :lives_with_both_parents], [:renewer, :parents_file_jointly])
    end

    it "asks who lives with them when the household list is missing" do
      results = FactGraph::Evaluator.evaluate({renewer: independent_filer}, graph_class: FactGraphs::Wa::IncomeStandardsOct2026)
      expect(WaHr1::Unknowns.missing_inputs(results, :household, :size)).to include([:household_members])
    end
  end
end

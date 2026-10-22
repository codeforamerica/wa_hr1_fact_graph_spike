# frozen_string_literal: true

RSpec.describe ImmigrationFacts do
  def immigration(renewer)
    results = FactGraph::Evaluator.evaluate({renewer: {renewal_month: "2027-03"}.merge(renewer)}, graph_class: FactGraphs::Wa::IncomeStandardsOct2026)
    [results[:immigration][:meets_citizenship_or_immigration], WaHr1::Unknowns.missing_inputs(results, :immigration, :meets_citizenship_or_immigration)]
  end

  it "accepts citizens without asking about LPR status" do
    expect(immigration(immigration_status: "us_citizen")).to eq [true, Set[]]
  end

  it "accepts Cuban/Haitian entrants and COFA migrants" do
    expect(immigration(immigration_status: "cuban_haitian_entrant").first).to be true
    expect(immigration(immigration_status: "cofa_migrant").first).to be true
  end

  it "no longer accepts refugees, asylees, parolees, and others who haven't become LPRs" do
    expect(immigration(immigration_status: "other_lawful_status").first).to be false
  end

  describe "lawful permanent residents and the 5-year bar" do
    let(:lpr) { {immigration_status: "lawful_permanent_resident", lpr_prior_status: "none", armed_forces_connection: false} }

    it "accepts someone who became an LPR 5 or more years ago" do
      expect(immigration(lpr.merge(became_lpr_on: "2022-03-15")).first).to be true
    end

    it "doesn't accept someone who became an LPR less than 5 years ago" do
      expect(immigration(lpr.merge(became_lpr_on: "2024-01-10")).first).to be false
    end

    it "accepts a recent LPR who was a refugee, which stays exempt from the bar" do
      expect(immigration(lpr.merge(became_lpr_on: "2024-01-10", lpr_prior_status: "refugee")).first).to be true
    end

    it "accepts a recent LPR with an armed forces connection" do
      expect(immigration(lpr.merge(became_lpr_on: "2024-01-10", armed_forces_connection: true)).first).to be true
    end

    it "asks only about the 5-year bar once we know someone is an LPR" do
      expect(immigration(immigration_status: "lawful_permanent_resident").last).to contain_exactly(
        [:renewer, :became_lpr_on], [:renewer, :lpr_prior_status], [:renewer, :armed_forces_connection]
      )
    end
  end
end

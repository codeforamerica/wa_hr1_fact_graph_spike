# frozen_string_literal: true

RSpec.describe FactGraphs::Wa::IncomeStandardsOct2026 do
  let(:standards) { FactGraph::Evaluator.evaluate({}, graph_class: described_class)[:standards] }

  it "combines federal, Washington, and income-period standards" do
    expect(standards).to include(
      min_monthly_income_cents: 58_000,
      renewal_lookback_months: 6,
      standards_effective: "2026-10-01"
    )
    expect(standards[:adult_income_limit_cents_by_household_size].first).to eq 183_500
  end
end

# frozen_string_literal: true

RSpec.describe WaHr1::WhatIf do
  let(:start) { {renewer: {renewal_month: "2027-03"}, work_requirement: {}} }

  def outcomes(path, input = start) = described_class.outcomes(path, input, WaHr1::JsonOutput::DEFAULT_TARGET)

  def by_label(path, input = start) = outcomes(path, input).to_h { [_1[:label], _1.except(:label)] }

  it "tries yes and no for a yes/no question" do
    expect(by_label([:renewer, :has_medicare])).to include(
      "yes" => {likely_eligible: false, remaining: 0},
      "no" => {likely_eligible: nil, remaining: be_positive}
    )
  end

  it "tries ages on each side of the rules" do
    expect(by_label([:renewer, :age]).transform_values { _1[:likely_eligible] }).to eq(
      "under 19" => false, "19 to 64" => nil, "65 or older" => false
    )
  end

  it "shows that one exclusion makes most of the work requirement's questions unnecessary" do
    frail = by_label([:work_requirement, :is_medically_frail])
    expect(frail["yes"][:remaining]).to be < frail["no"][:remaining] - 10
  end

  it "tries an upload that meets the work requirement and one that falls short" do
    activity = by_label([:months])
    expect(activity.keys).to eq ["meets the work requirement", "falls short"]
    expect(activity["meets the work requirement"][:remaining]).to be < activity["falls short"][:remaining]
  end

  it "tries each immigration status" do
    statuses = by_label([:renewer, :immigration_status])
    expect(statuses.keys).to match_array(ImmigrationFacts::STATUSES)
    expect(statuses["other_lawful_status"][:likely_eligible]).to be false
  end

  it "gives no candidates for inputs it can't simulate, like a date pattern without context" do
    expect(described_class.candidates([:renewer, :renewal_month], start)).to eq []
  end

  it "only runs when asked, since it evaluates the graph many times" do
    without = WaHr1::JsonOutput.evaluate(start)[:next_questions].map { _1[:what_if] }
    with = WaHr1::JsonOutput.evaluate(start, what_if: true)[:next_questions].map { _1[:what_if] }
    expect(without).to all(be_nil)
    expect(with).to all(be_an(Array))
  end
end

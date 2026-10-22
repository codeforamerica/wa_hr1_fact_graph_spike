# frozen_string_literal: true

RSpec.describe WaHr1::Input do
  describe ".with_sections" do
    it "adds the hash sections that are missing, keeping what's there" do
      expect(described_class.with_sections(renewer: {age: 30})).to eq(renewer: {age: 30}, work_requirement: {})
    end

    it "doesn't add list sections, where an empty list is an answer" do
      expect(described_class.with_sections({}).keys).not_to include(:household_members, :months)
    end

    it "lets the walker name each question in a section instead of the whole section" do
      results = FactGraph::Evaluator.evaluate(described_class.with_sections({}), graph_class: FactGraphs::Wa::IncomeStandardsOct2026)
      paths = WaHr1::Unknowns.missing_inputs(results, :work_requirement, :has_exclusion)
      expect(paths).to include([:work_requirement, :is_medically_frail])
      expect(paths).not_to include([:work_requirement])
    end
  end
end

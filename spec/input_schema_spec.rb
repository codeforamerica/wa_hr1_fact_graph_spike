# frozen_string_literal: true

require "json"
require_relative "../lib/wa_hr1/input_schema"
require_relative "../lib/wa_hr1/json_output"

RSpec.describe WaHr1::InputSchema do
  let(:schema) { described_class.generate(FactGraphs::Wa::IncomeStandardsOct2026) }

  it "describes every input the graph reads" do
    undescribed = described_class.input_paths(schema).reject { WaHr1::INPUT_DESCRIPTIONS.key?(_1) }
    expect(undescribed).to be_empty
  end

  it "has no descriptions for inputs that don't exist" do
    expect { schema }.not_to raise_error
  end

  it "doesn't require anything up front" do
    expect(schema).not_to have_key("required")
    expect(schema.dig("properties", "renewer")).not_to have_key("required")
    expect(schema.dig("properties", "months", "items")).not_to have_key("required")
  end

  it "keeps the fixed structure of an income item" do
    item = schema.dig("properties", "months", "items", "properties", "income_items", "items")
    expect(item["required"]).to contain_exactly("type", "amount_cents", "frequency")
    expect(item.dig("properties", "type", "enum")).to include("wages", "work_study")
  end

  it "uses JSON Schema regex anchors" do
    pattern = schema.dig("properties", "renewer", "properties", "renewal_month", "pattern")
    expect(pattern).to start_with("^").and end_with("$")
  end

  it "matches the checked-in copy in schema/input.schema.json (regenerate with bin/input-schema)" do
    checked_in = JSON.parse(File.read(File.expand_path("../schema/input.schema.json", __dir__)))
    expect(checked_in).to eq JSON.parse(JSON.generate(schema))
  end
end

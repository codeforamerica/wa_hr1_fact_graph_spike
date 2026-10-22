# frozen_string_literal: true

RSpec.describe WaHr1::JsonOutput do
  def questions(input) = described_class.evaluate(input)[:next_questions]

  it "describes each next question and the values it accepts" do
    question = questions(renewer: {renewal_month: "2027-03"}).find { _1[:path] == %w[renewer immigration_status] }
    expect(question[:description]).to include("citizenship or immigration status")
    expect(question[:schema]).to include("type" => "string", "enum" => include("us_citizen", "lawful_permanent_resident"))
  end

  it "gives the item structure for list inputs, so an agent can build them" do
    question = questions(renewer: {renewal_month: "2027-03"}).find { _1[:path] == %w[household_members] }
    expect(question.dig(:schema, "items", "properties", "relationship_to_renewer", "enum")).to include("parent", "spouse")
  end

  it "finds the schema through a list index" do
    input = {renewer: {renewal_month: "2027-03"}, household_members: [], months: [{month: "2027-03"}]}
    question = questions(input).find { _1[:path] == ["months", 0, "income_items"] }
    expect(question.dig(:schema, "items", "properties", "type", "enum")).to include("work_study")
  end
end

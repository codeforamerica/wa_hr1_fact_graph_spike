# frozen_string_literal: true

class LogicTestGraph < FactGraph::Graph
  in_module :test do
    fact(:a) { input [:test, :a], value: :bool? }
    fact(:b) { input [:test, :b], value: :bool? }
    fact(:c) { input [:test, :c], value: :bool? }

    fact :any_abc, allow_unmet_dependencies: true do
      dependency :a
      dependency :b
      dependency :c
      proc { WaHr1::Logic.any_of(data[:dependencies]) }
    end

    fact :all_abc, allow_unmet_dependencies: true do
      dependency :a
      dependency :b
      dependency :c
      proc { WaHr1::Logic.all_of(data[:dependencies]) }
    end

    # A downstream fact that doesn't opt in to unmet dependencies, to check that a hand-built
    # Error is treated like any other unknown.
    fact :not_any_abc do
      dependency :any_abc
      proc { !data[:dependencies][:any_abc] }
    end
  end

  in_module :months do
    fact :met, per_entity: :months do
      input :met, per_entity: true, value: :bool?
    end
  end

  in_module :summary do
    fact :naive_any_month_met do
      dependency :met, from: :months
      proc { data[:dependencies][:met].values.any?(true) }
    end

    fact :any_month_met, allow_unmet_dependencies: true do
      input :months do
        required(:months).array(:hash)
      end
      dependency :met, from: :months

      proc do
        # allow_unmet_dependencies also lets the resolver run when its own input is invalid.
        next data_errors unless data[:input][:months].is_a?(Array)

        entity_ids = (0...data[:input][:months].count).to_a
        WaHr1::Logic.any_entity(data[:dependencies][:met], entity_ids:, fact: [:months, :met])
      end
    end
  end
end

RSpec.describe WaHr1::Logic do
  def evaluate(input) = FactGraph::Evaluator.evaluate(input, graph_class: LogicTestGraph)

  describe ".any_of" do
    it "is true as soon as one value is true, even if others are unknown" do
      expect(evaluate({test: {a: true}})[:test][:any_abc]).to be true
    end

    it "is false when every value is false" do
      expect(evaluate({test: {a: false, b: false, c: false}})[:test][:any_abc]).to be false
    end

    it "is unknown when nothing is true and something is unknown, naming only the unknowns" do
      result = evaluate({test: {a: false}})[:test][:any_abc]
      expect(result).to unknown
      expect(result.fact_bad_inputs.keys).to contain_exactly([:test, :b], [:test, :c])
    end
  end

  describe ".all_of" do
    it "is false as soon as one value is false, even if others are unknown" do
      expect(evaluate({test: {b: false}})[:test][:all_abc]).to be false
    end

    it "is true when every value is true" do
      expect(evaluate({test: {a: true, b: true, c: true}})[:test][:all_abc]).to be true
    end

    it "is unknown when nothing is false and something is unknown, naming only the unknowns" do
      result = evaluate({test: {a: true, c: true}})[:test][:all_abc]
      expect(result.fact_bad_inputs.keys).to eq [[:test, :b]]
    end

    it "rejects values that aren't true, false, or unknown" do
      expect { described_class.all_of([true, nil]) }.to raise_error(ArgumentError)
    end
  end

  it "treats a hand-built Error like any other unknown downstream" do
    result = evaluate({test: {a: false}})[:test][:not_any_abc]
    expect(result).to unknown
    expect(result.fact_dependency_unmet).to eq({test: [:any_abc]})
  end

  describe "aggregating per-entity facts" do
    let(:input) { {months: [{met: false}, {}, {met: false}]} }

    it "fact_graph drops unknown entities from the aggregate, so a naive 'any' answers false" do
      expect(evaluate(input)[:summary][:naive_any_month_met]).to be false
    end

    it ".any_entity counts a dropped entity as unknown" do
      result = evaluate(input)[:summary][:any_month_met]
      expect(result).to unknown
      expect(result.fact_dependency_unmet).to eq({months: [:met]})
    end

    it ".any_entity is true when any entity is true, whatever the others are" do
      expect(evaluate({months: [{}, {met: true}]})[:summary][:any_month_met]).to be true
    end

    it ".any_entity is false when every entity is false" do
      expect(evaluate({months: [{met: false}, {met: false}]})[:summary][:any_month_met]).to be false
    end
  end
end

RSpec.describe WaHr1::Unknowns do
  def evaluate(input) = FactGraph::Evaluator.evaluate(input, graph_class: LogicTestGraph)

  it "follows unknowns down to the inputs still needed, skipping ones that no longer matter" do
    results = evaluate({test: {a: false}})
    expect(described_class.missing_inputs(results, :test, :not_any_abc)).to contain_exactly([:test, :b], [:test, :c])
  end

  it "finds nothing when the fact is decided" do
    results = evaluate({test: {b: true}})
    expect(described_class.missing_inputs(results, :test, :not_any_abc)).to be_empty
  end

  it "finds the exact entity input that's missing" do
    results = evaluate({months: [{met: false}, {}, {met: false}]})
    expect(described_class.missing_inputs(results, :summary, :any_month_met)).to contain_exactly([:months, 1, :met])
  end
end

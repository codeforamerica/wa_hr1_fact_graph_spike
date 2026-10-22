# frozen_string_literal: true

require "json"

module WaHr1
  # Evaluates renewal input given as JSON-style data and returns JSON-safe output for an agent.
  module JsonOutput
    GRAPH = FactGraphs::Wa::IncomeStandardsOct2026
    DEFAULT_TARGET = [:eligibility, :likely_eligible].freeze

    module_function

    # input: a Hash with symbol keys, as from JSON.parse(..., symbolize_names: true).
    # target: the [module, fact] whose missing inputs become next_questions.
    def evaluate(input, target: DEFAULT_TARGET)
      input = Input.with_sections(input)
      results = FactGraph::Evaluator.evaluate(input, graph_class: GRAPH)
      messages = FactGraph::Evaluator.input_errors(results)

      {
        graph: GRAPH.name,
        standards_effective: results.dig(:standards, :standards_effective),
        likely_eligible: value(results.dig(:eligibility, :likely_eligible)),
        likely_eligible_for_family_coverage_instead: value(results.dig(:eligibility, :likely_eligible_for_family_coverage_instead)),
        target: target.join("."),
        next_questions: Unknowns.missing_inputs(results, *target).map { |path| question(path, input, messages) },
        facts: results.transform_values { |facts| facts.transform_values { value(_1) } }
      }
    end

    # Unknowns become nil, and per-entity results become arrays indexed by entity ID.
    def value(result)
      case result
      when FactGraph::Error then nil
      when Hash
        if Unknowns.per_entity_result?(result)
          size = result.empty? ? 0 : result.keys.max + 1
          Array.new(size) { |id| value(result[id]) }
        else
          result.transform_values { value(_1) }
        end
      when Array then result.map { value(_1) }
      else result
      end
    end

    # "missing" when the input doesn't have the path; "invalid" when it does but the value was rejected.
    def question(path, input, messages)
      {
        path: path.map { _1.is_a?(Symbol) ? _1.to_s : _1 },
        status: present?(input, path) ? "invalid" : "missing",
        messages: messages.fetch(path, Set[]).to_a
      }
    end

    def present?(input, path)
      path.reduce(input) do |node, key|
        case node
        when Hash then node.key?(key) ? node[key] : (return false)
        when Array then key.is_a?(Integer) && key < node.size ? node[key] : (return false)
        else return false
        end
      end
      true
    end
  end
end

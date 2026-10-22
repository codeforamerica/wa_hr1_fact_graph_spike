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
    # what_if: also try representative answers to each next question (WaHr1::WhatIf).
    def evaluate(input, target: DEFAULT_TARGET, what_if: false)
      input = Input.with_sections(input)
      results = FactGraph::Evaluator.evaluate(input, graph_class: GRAPH)
      messages = FactGraph::Evaluator.input_errors(results)

      {
        protocol_version: PROTOCOL_VERSION,
        graph: GRAPH.name,
        standards_effective: results.dig(:standards, :standards_effective),
        likely_eligible: value(results.dig(:eligibility, :likely_eligible)),
        likely_eligible_for_family_coverage_instead: value(results.dig(:eligibility, :likely_eligible_for_family_coverage_instead)),
        target: target.join("."),
        next_questions: Unknowns.missing_inputs(results, *target).map do |path|
          question(path, input, messages).merge(what_if: what_if ? WhatIf.outcomes(path, input, target) : nil)
        end,
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
    # One input still needed. description and schema come from the input JSON Schema, so an agent
    # knows what the question means and which values it accepts.
    def question(path, input, messages)
      schema = schema_for(path)
      {
        path: path.map { _1.is_a?(Symbol) ? _1.to_s : _1 },
        status: present?(input, path) ? "invalid" : "missing",
        messages: messages.fetch(path, Set[]).to_a,
        description: schema&.fetch("description", nil),
        schema:
      }
    end

    # The JSON Schema fragment for an input path. Integer segments index into a list's items.
    def schema_for(path)
      path.reduce(input_schema) do |node, key|
        return nil if node.nil?

        if key.is_a?(Integer)
          node["items"]
        else
          node.dig("properties", key.to_s)
        end
      end
    end

    def input_schema
      @input_schema ||= InputSchema.generate(GRAPH).except("$schema", "title", "description")
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

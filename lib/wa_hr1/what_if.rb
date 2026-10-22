# frozen_string_literal: true

module WaHr1
  # What each answer to a next question would lead to. For each question the graph still needs, a
  # few representative answers are tried on a copy of the input, and each reports whether the
  # target fact would be decided and how many questions would remain. An agent combines these with
  # how likely each answer is for this person to choose the question that ends the conversation
  # soonest.
  #
  # Representative answers are domain knowledge: the values that land on different sides of the
  # rules (an age under 19, between 19 and 64, and 65 or over), not every possible value.
  module WhatIf
    module_function

    # [{label:, answers: [[path, value], ...]}] for one question, or [] if it can't be simulated.
    def candidates(path, input)
      path = path.map { _1.is_a?(Symbol) ? _1.to_s : _1 }
      leaf = path.last
      case [path.first, leaf]
      in ["months", _] if path.size == 1
        activity_candidates(input)
      in [_, "income_items"]
        [
          {label: "none", answers: [[path, []]]},
          {label: "about $500 a month in wages", answers: [[path, [wages(50_000)]]]},
          {label: "about $3,000 a month in wages", answers: [[path, [wages(300_000)]]]}
        ]
      in ["household_members", _] if path.size == 1
        [
          {label: "nobody else", answers: [[path, []]]},
          {label: "a parent who claims them as a tax dependent", answers: [[path, [CLAIMING_PARENT]]]},
          {label: "a spouse they live with", answers: [[path, [SPOUSE]]]}
        ]
      in [_, "age"]
        [17, 30, 70].map { {label: age_label(_1), answers: [[path, _1]]} }
      in [_, "immigration_status"]
        ImmigrationFacts::STATUSES.map { {label: _1, answers: [[path, _1]]} }
      in [_, "lpr_prior_status"]
        [{label: "none", answers: [[path, "none"]]}, {label: "refugee or asylee", answers: [[path, "refugee"]]}]
      in [_, "became_lpr_on"]
        renewal = input.dig(:renewer, :renewal_month) || "2027-03"
        year = renewal[0, 4].to_i
        [
          {label: "less than 5 years ago", answers: [[path, "#{year - 2}-01-01"]]},
          {label: "5 or more years ago", answers: [[path, "#{year - 10}-01-01"]]}
        ]
      in [_, "expected_unborn_children"]
        [{label: "1", answers: [[path, 1]]}]
      in [_, "credit_hours"]
        [{label: "0", answers: [[path, 0]]}, {label: "6", answers: [[path, 6]]}]
      else
        boolean?(path) ? [{label: "yes", answers: [[path, true]]}, {label: "no", answers: [[path, false]]}] : generic(path)
      end
    end

    # Whether the work requirement's monthly activity, from an upload or answers, would settle it.
    def activity_candidates(input)
      renewal = input.dig(:renewer, :renewal_month)
      return [] unless renewal

      lookback = Months.before(renewal, 6)
      existing = Array(input[:months]).reject { lookback.include?(_1[:month]) }
      settles = lookback.map { {month: _1, in_education_program: true, enrolled_at_least_half_time: true, income_items: []} }
      falls_short = lookback.map do
        {month: _1, in_education_program: false, work_hours: 0, work_program_hours: 0, community_service_hours: 0, income_items: []}
      end
      [
        {label: "meets the work requirement", answers: [[[:months], existing + settles]]},
        {label: "falls short", answers: [[[:months], existing + falls_short]]}
      ]
    end

    # The candidates' outcomes for one question: [{label:, likely_eligible:, remaining:}].
    def outcomes(path, input, target)
      candidates(path, input).map do |candidate|
        hypothetical = candidate[:answers].reduce(deep_dup(input)) { |acc, (p, v)| set(acc, p, v) }
        results = FactGraph::Evaluator.evaluate(Input.with_sections(hypothetical), graph_class: JsonOutput::GRAPH)
        decided = JsonOutput.value(results.dig(*target))
        remaining = decided.nil? ? Unknowns.missing_inputs(results, *target).size : 0
        {label: candidate[:label], likely_eligible: decided, remaining:}
      end
    end

    CLAIMING_PARENT = {relationship_to_renewer: "parent", lives_with_renewer: false, claims_renewer_as_dependent: true}.freeze
    SPOUSE = {relationship_to_renewer: "spouse", lives_with_renewer: true}.freeze

    def wages(cents) = {type: "wages", amount_cents: cents, frequency: "monthly"}

    def age_label(age)
      return "under 19" if age < 19
      return "65 or older" if age >= 65

      "19 to 64"
    end

    def boolean?(path)
      JsonOutput.schema_for(path)&.fetch("type", nil) == "boolean"
    end

    def generic(path)
      schema = JsonOutput.schema_for(path)
      return [] unless schema && schema["type"] == "integer"

      [{label: "0", answers: [[path, 0]]}, {label: "100", answers: [[path, 100]]}]
    end

    def set(input, path, value)
      keys = path.map { _1.is_a?(String) ? _1.to_sym : _1 }
      node = keys[0..-2].each_with_index.reduce(input) do |current, (key, index)|
        current[key] ||= keys[index + 1].is_a?(Integer) ? [] : {}
      end
      node[keys.last] = value
      input
    end

    def deep_dup(value)
      case value
      when Hash then value.to_h { |k, v| [k, deep_dup(v)] }
      when Array then value.map { deep_dup(_1) }
      else value
      end
    end
  end
end

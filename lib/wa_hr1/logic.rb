# frozen_string_literal: true

module WaHr1
  # Three-valued logic for fact resolvers. A value is true, false, or unknown (a FactGraph::Error).
  # Use these in facts declared with `allow_unmet_dependencies: true`, so the resolver runs even
  # when some dependencies are unknown.
  #
  # When the answer is unknown, the result is an Error built only from the dependencies that could
  # still change the answer. Facts that are already decided, or that don't matter, never show up in
  # it, so the unknowns that reach the top of the graph are the questions worth asking.
  module Logic
    module_function

    def unknown?(value) = value.is_a?(FactGraph::Error)

    # True if any value is true, false if every value is false, otherwise unknown.
    def any_of(values)
      values = check_booleans(values)
      return true if values.any?(true)
      return false if values.all?(false)

      merge_unknowns(values.select { unknown?(_1) })
    end

    # False if any value is false, true if every value is true, otherwise unknown.
    def all_of(values)
      values = check_booleans(values)
      return false if values.any?(false)
      return true if values.all?(true)

      merge_unknowns(values.select { unknown?(_1) })
    end

    # A fact that isn't per-entity receives a per-entity dependency as {entity_id => value}, but
    # fact_graph leaves out entities whose value is unknown. Pass the entity IDs that exist (from
    # the fact's input) so a missing entity counts as unknown rather than silently disappearing.
    # `fact` is the [module, name] of the per-entity fact, used to name the unknowns.
    def any_entity(values_by_id, entity_ids:, fact:)
      any_of(with_missing_entities(values_by_id, entity_ids, fact))
    end

    def all_entities(values_by_id, entity_ids:, fact:)
      all_of(with_missing_entities(values_by_id, entity_ids, fact))
    end

    def merge_unknowns(errors)
      bad_inputs = {}
      unmet = {}
      errors.each do |error|
        error.fact_bad_inputs.each { |path, messages| (bad_inputs[path] ||= Set.new).merge(messages) }
        error.fact_dependency_unmet.each { |module_name, facts| unmet[module_name] = (unmet[module_name] || []) | facts }
      end
      FactGraph::Error.new(fact_bad_inputs: bad_inputs, fact_dependency_unmet: unmet)
    end

    def with_missing_entities(values_by_id, entity_ids, fact)
      module_name, fact_name = fact
      missing = entity_ids - values_by_id.keys
      return values_by_id.values if missing.empty?

      values_by_id.values + [FactGraph::Error.new(fact_bad_inputs: {}, fact_dependency_unmet: {module_name => [fact_name]})]
    end

    def check_booleans(values)
      values = values.values if values.is_a?(Hash)
      bad = values.reject { |v| v == true || v == false || unknown?(v) }
      raise ArgumentError, "expected true, false, or FactGraph::Error, got #{bad.inspect}" unless bad.empty?

      values
    end
  end
end

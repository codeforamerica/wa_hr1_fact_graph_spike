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

    # Like all_of, but when the answer is unknown it names only the first unknown value. For
    # conditions that are follow-ups to the ones before them, like "is an LPR" then "has been one for
    # 5 years": the follow-up isn't worth asking until its gate is known to be true. Still false as
    # soon as any value is known to be false.
    def gated_all_of(values)
      values = check_booleans(values)
      return false if values.any?(false)
      return true if values.all?(true)

      values.find { unknown?(_1) }
    end

    # Not, keeping unknowns unknown.
    def negate(value) = unknown?(value) ? value : !check_booleans([value]).first

    # The values for every entity, or unknown if any entity's value is unknown. For aggregates,
    # like a count or a sum, that need every entity.
    def every_entity(values_by_id, entity_ids:, fact:)
      values = with_missing_entities(values_by_id, entity_ids, fact)
      unknowns = values.select { unknown?(_1) }
      unknowns.empty? ? values_by_id : merge_unknowns(unknowns)
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

    # An unknown waiting on one entity's value of a per-entity fact. See WaHr1::Unknowns.
    def unknown_entity(module_name, fact_name, entity_id)
      FactGraph::Error.new(fact_bad_inputs: {}, fact_dependency_unmet: {module_name => [[fact_name, entity_id]]})
    end

    def with_missing_entities(values_by_id, entity_ids, fact)
      module_name, fact_name = fact
      missing = entity_ids - values_by_id.keys
      values_by_id.values + missing.map { |id| unknown_entity(module_name, fact_name, id) }
    end

    # A per-entity fact's values as an array indexed by entity ID, with nil where the value is
    # unknown. For publishing per-entity values to facts about a different kind of entity, which
    # fact_graph can't connect directly.
    def values_by_index(values_by_id, entity_ids)
      entity_ids.map { |id| values_by_id.fetch(id, nil) }
    end

    def check_booleans(values)
      values = values.values if values.is_a?(Hash)
      bad = values.reject { |v| v == true || v == false || unknown?(v) }
      raise ArgumentError, "expected true, false, or FactGraph::Error, got #{bad.inspect}" unless bad.empty?

      values
    end
  end
end

# Resolvers run with a FactGraph::DataContainer as self, so this lets them call any_of, all_of,
# and the rest directly.
FactGraph::DataContainer.include(WaHr1::Logic)

# frozen_string_literal: true

module WaHr1
  # Finds which inputs are still needed to decide a fact, by following the unknowns in its result
  # down to the input facts they come from. The paths it returns are input key paths, like
  # [:renewer, :age] or [:months, 2, :work_hours].
  module Unknowns
    module_function

    def missing_inputs(results, module_name, fact_name, entity_id: nil)
      paths = Set.new
      walk(results, module_name, fact_name, entity_id, paths, Set.new)
      paths
    end

    def walk(results, module_name, fact_name, entity_id, paths, visited)
      return unless visited.add?([module_name, fact_name, entity_id])

      value = results.dig(module_name, fact_name)
      if per_entity_result?(value)
        targets = entity_id.nil? ? value : value.slice(entity_id)
        targets.each { |id, entity_value| walk_value(results, entity_value, id, paths, visited) }
      else
        walk_value(results, value, entity_id, paths, visited)
      end
    end

    def walk_value(results, value, entity_id, paths, visited)
      return unless value.is_a?(FactGraph::Error)

      paths.merge(value.fact_bad_inputs.keys)
      value.fact_dependency_unmet.each do |module_name, fact_names|
        fact_names.each { |fact_name| walk(results, module_name, fact_name, entity_id, paths, visited) }
      end
    end

    # Per-entity facts resolve to {entity_id => value}. Our graphs never use a hash with integer keys
    # as a fact's own value, so that shape is enough to tell them apart.
    def per_entity_result?(value)
      value.is_a?(Hash) && value.keys.all?(Integer)
    end
  end
end

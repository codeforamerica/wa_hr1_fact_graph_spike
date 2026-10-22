# frozen_string_literal: true

require "dry/schema"
require_relative "input_descriptions"

Dry::Schema.load_extensions(:json_schema)

module WaHr1
  # A JSON Schema for the graph's input, built from the input definitions of every fact in the graph,
  # so it can't drift from what the graph actually reads. Descriptions come from
  # WaHr1::INPUT_DESCRIPTIONS, keyed by path ("renewer.age", "months[].work_hours").
  module InputSchema
    module_function

    def generate(graph)
      root = {"type" => "object", "properties" => {}}
      graph.fact_objects.each do |fact|
        fact.input_definitions.each_value do |definition|
          schema = definition[:validator].json_schema.except(:$schema)
          if definition[:per_entity]
            list = root["properties"][fact.per_entity.to_s] ||= {"type" => "array", "items" => {"type" => "object", "properties" => {}}}
            deep_merge!(list["items"], stringify(schema))
          else
            deep_merge!(root, stringify(schema))
          end
        end
      end
      strip_section_requirements!(root)
      js_patterns!(root)
      describe!(root)
      {"$schema" => "https://json-schema.org/draft/2020-12/schema", "title" => "Washington Apple Health for Adults renewal input"}
        .merge(root)
        .merge("description" => INPUT_DESCRIPTIONS.fetch(""))
    end

    # Every path that takes a value from the person, like "renewer.age" or "months[].income_items".
    def input_paths(schema)
      schema["properties"].flat_map do |section, section_schema|
        props = section_schema["type"] == "array" ? section_schema.dig("items", "properties") : section_schema["properties"]
        separator = section_schema["type"] == "array" ? "[]." : "."
        (props || {}).keys.map { |key| "#{section}#{separator}#{key}" }
      end
    end

    def stringify(value)
      case value
      when Hash then value.to_h { |k, v| [k.to_s, stringify(v)] }
      when Array then value.map { stringify(_1) }
      when Symbol then value.to_s
      else value
      end
    end

    def deep_merge!(target, source)
      source.each do |key, value|
        target[key] = if target[key].is_a?(Hash) && value.is_a?(Hash)
          deep_merge!(target[key], value)
        elsif target[key].is_a?(Array) && value.is_a?(Array)
          target[key] | value
        else
          value
        end
      end
      target
    end

    # Nothing is required up front: a missing answer is a question to ask. Only the structure of an
    # income item is fixed.
    def strip_section_requirements!(root)
      root.delete("required")
      root["properties"].each_value do |section|
        section.delete("required")
        section["items"]&.delete("required")
      end
    end

    # Ruby's \A and \z anchors aren't valid in JSON Schema patterns.
    def js_patterns!(node)
      case node
      when Hash
        node["pattern"] = node["pattern"].gsub("\\A", "^").gsub("\\z", "$") if node["pattern"].is_a?(String)
        node.each_value { js_patterns!(_1) }
      when Array then node.each { js_patterns!(_1) }
      end
    end

    def describe!(root)
      INPUT_DESCRIPTIONS.each do |path, text|
        next if path.empty?

        node = path.split(".").reduce(root) do |current, key|
          list = key.end_with?("[]")
          child = current.fetch("properties").fetch(key.delete_suffix("[]")) { raise KeyError, "no input at #{path}" }
          list ? child.fetch("items") : child
        end
        node["description"] = text
      end
    end
  end
end

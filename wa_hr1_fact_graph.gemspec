# frozen_string_literal: true

require_relative "lib/wa_hr1/version"

Gem::Specification.new do |spec|
  spec.name = "wa_hr1_fact_graph"
  spec.version = WaHr1::VERSION
  spec.authors = ["Code for America"]
  spec.summary = "Washington Apple Health for Adults eligibility under H.R. 1, as a fact graph."
  spec.description = "A spike: Washington's Apple Health for Adults rules (household, income, work requirement, " \
    "immigration) as a codeforamerica/fact_graph graph, with a JSON command that reports likely eligibility, " \
    "the next questions to ask, and every intermediate fact."
  spec.homepage = "https://github.com/codeforamerica/wa_hr1_fact_graph_spike"
  spec.required_ruby_version = ">= 4.0.6"

  spec.files = Dir["lib/**/*.rb", "exe/*", "schema/*.json", "README.md"]
  spec.bindir = "exe"
  spec.executables = ["wa-hr1-evaluate", "wa-hr1-input-schema"]
  spec.require_paths = ["lib"]

  # fact_graph isn't on rubygems.org; the Gemfile of whatever uses this gem says where to get it.
  spec.add_dependency "fact_graph", "~> 0.1"
  spec.add_dependency "activesupport", "~> 8.0"
  spec.add_dependency "dry-schema", "~> 1.13"
  spec.add_dependency "json", ">= 2.0"
end

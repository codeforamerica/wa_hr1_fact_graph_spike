# Washington Apple Health for Adults: fact graph spike

A temporary spike for Team Orange's SameSite 2026 prototype (`samesite2026-app-02`). The goal is to find out whether
[fact_graph](https://github.com/codeforamerica/fact_graph) can represent Washington's Apple Health for Adults eligibility
under H.R. 1, so that a chat agent can:

- tell someone whether they're likely eligible,
- ask the most important next question when it can't tell yet, and
- explain the answer from the graph's own intermediate facts.

How this would plug into the Python app is a separate decision for after the spike.

## Running it

Needs Ruby 4.0.6 and a checkout of `fact_graph` next to this directory, on the `fix-query-helpers-per-entity` branch
(codeforamerica/fact_graph#36).

```sh
bundle install
bundle exec rspec
```

## Design

Sources are indexed in the app repo's `docs/README.md`. The main ones are the WAC rules in `docs/resources/wac-*.txt`,
HCA's income standards chart, and HCA's August 2026 analysis of the work requirement.

- **Small facts.** Each fact answers one question. Combined facts are "any of" or "all of" smaller ones, so the agent
  can read why from the values. There are no reason codes.
- **Unknown is an Error.** `WaHr1::Logic.any_of` / `all_of` decide what they can from partial information. When they
  can't, they return an Error naming only the unknowns that still matter. `WaHr1::Unknowns.missing_inputs` follows those
  down to the input paths still needed: the candidates for the next question.
- **We trust what people tell us.** One evaluation, no proof checking.
- **JSON-safe values.** Money is integer cents, dates and months are ISO 8601 strings, enums are strings.
- **Graph layers.**
  - `FactGraphs::Base`: the federal rules.
  - `FactGraphs::States::Wa`: Washington's choices.
  - `FactGraphs::Wa::IncomeStandardsOct2026`: one income-standards period, and the graph we evaluate.

### Planned modules

| Module | What it decides |
|---|---|
| `standards` | Constants: income limits, $580, 80 hours, the credit-hour table, the federal minimum wage. |
| `general` | Age, Medicare, other mandatory programs, residency, SSN. |
| `household` | Who's in the renewer's household (WAC 182-506-0010/-0012); household size; whose income counts (WAC 182-509-0360). |
| `income` | Countable monthly income from tagged income items, including pay frequency (WAC 182-509-0310) and exclusions (0335, 0340); the income limit. |
| `immigration` | H.R. 1's qualified noncitizen definition, the 5-year bar and its exemptions. |
| `work_requirement` | Exclusions, exemptions, and per-month activities, including the seasonal-worker average and hours from income. |
| `eligibility` | `likely_eligible`, and `likely_eligible_for_family_coverage_instead`. |

### Shortcuts

- **Filing requirement.** Whether a tax dependent is required to file taxes is something the user tells us; we don't
  encode IRS thresholds.
- **Family program.** Parents and caretakers under the family income limit get a `likely_eligible_for_family_coverage_instead`
  fact instead of a model of that program.
- **Hours from income.** Uses the renewer's own earned income ("a reasonable method" under 42 CFR 435.552(e)(2)).
- **Out of scope:** other Apple Health programs, retroactive coverage, cost sharing, first-time applications, and proof.

## Findings so far

1. **A fact can return a hand-built `FactGraph::Error`.** Downstream facts treat it like any other unknown. That's
   what makes `any_of` / `all_of` and the next-question walker possible.
2. **Aggregates silently drop unknown entities.** A fact that isn't per-entity receives a per-entity dependency with
   the unknown entities removed, so a naive "any month meets the requirement" answers false when one month is unknown.
   `any_entity` / `all_entities` take the entity IDs from the fact's input to correct for it. This might be worth
   changing in fact_graph for facts that opt in to `allow_unmet_dependencies`.
3. **`allow_unmet_dependencies` also lets a resolver run when its own input is invalid**, so those resolvers must
   check their inputs (`next data_errors unless ...`).
4. **A fact can't depend on two facts with the same name from different modules.** Dependencies are keyed by fact
   name alone (there's a TODO about this in `fact.rb`). The household rules hit this with the renewer's `under_19` and
   a member's `under_19`. We worked around it with an intermediate fact (`renewer_is_nonfiler_under_19`), which is the
   kind of small fact we want anyway.
5. **Resolvers can't reach shared helpers without a monkeypatch.** They run with a `FactGraph::DataContainer` as
   `self`, so `logic.rb` includes our helpers into that class. A supported hook for this would be cleaner.
6. **The next-question walker exposes silly questions, and we fix them in the graph.** The first household version
   asked whether Maya's mom claims Maya's dad as a tax dependent. Ruling out the claimer and the claimer's spouse
   before asking (in `in_household_as_renewers_claimers_tax_dependent`) removed it. Expect to tune the graph this
   way. Order doesn't matter in `all_of` / `any_of`: one known false (or true) decides them. What helps is adding
   dependencies we usually already know that can rule a branch out. When several unknowns remain, all of them are
   named, and choosing which to ask first is up to the agent.
7. **A per-entity fact that depends on a per-entity fact of a *different* entity type silently gets the wrong
   entity.** fact_graph picks the dependency's entity with the same ID, so a month's fact would see the household
   member whose index equals the month's index. There's no error. We avoid it by publishing per-member values as an
   array from a fact that isn't per-entity (`household.income_counts_by_member`), which month facts can read. fact_graph
   should probably refuse this kind of dependency, or let a fact say which entity type it's indexing.
8. **Unknowns can point at one entity.** We name a specific entity as `[fact, entity_id]` in an Error's
   `fact_dependency_unmet`, and the walker follows only that entity. fact_graph doesn't look inside those lists, so
   this works today, but it's our convention, not the library's.

# frozen_string_literal: true

module WaHr1
  # Descriptions for the input JSON Schema (WaHr1::InputSchema), keyed by path. "" describes the whole
  # input. "x[]" is the item in list x. spec/input_schema_spec.rb checks that every input has one.
  INPUT_DESCRIPTIONS = {
    "" => <<~TEXT.strip,
      What a person renewing Washington Apple Health for Adults has told us. Every field is optional: leave out anything
      you don't know yet, and never send null. The graph's next_questions output says what to ask next.
      Hash sections (renewer, work_requirement) should always be sent, as {} if empty. List sections (household_members,
      months) should be sent only once you know what's in them, because an empty list is an answer.
      Money is integer cents. Months are "YYYY-MM"; dates are "YYYY-MM-DD".
      Record only what the person says; the graph applies the rules.
    TEXT

    # renewer
    "renewer" => "About the person renewing. Always send, as {} if nothing is known.",
    "renewer.renewal_month" => "The month their coverage renews, like \"2027-03\". On their renewal letter, or at wahealthplanfinder.org.",
    "renewer.age" => "Their age in years.",
    "renewer.pregnant" => "Whether they're pregnant now.",
    "renewer.has_medicare" => "Whether they have Medicare Part A or Part B.",
    "renewer.expected_unborn_children" => "If pregnant, how many babies they're expecting.",
    "renewer.expects_to_file_taxes" => "Whether they expect to file a federal tax return for this year.",
    "renewer.expects_to_be_claimed_as_dependent" => "Whether they expect someone else to claim them as a tax dependent this year.",
    "renewer.claimed_by_parent" => "If someone claims them as a tax dependent: whether that person is their parent, including a stepparent or adoptive parent.",
    "renewer.claimed_by_noncustodial_parent" => "If a parent claims them: whether that parent is a noncustodial parent (one they don't live with most of the time).",
    "renewer.lives_with_both_parents" => "Only for someone under 19: whether they live with both parents.",
    "renewer.parents_file_jointly" => "Only for someone under 19 who lives with both parents: whether their parents file a joint tax return.",
    "renewer.required_to_file_taxes" => "If they're a tax dependent: whether their own income is high enough that they're required to file a tax return.",
    "renewer.in_medical_institution_30_days" => "Whether they've lived in a hospital, nursing facility, or inpatient psychiatric facility for 30 days in a row, or are expected to.",
    "renewer.immigration_status" => "Their citizenship or immigration status. Use other_lawful_status for refugees, asylees, parolees, and other lawful statuses that haven't become permanent residence.",
    "renewer.became_lpr_on" => "For lawful permanent residents: the date they became one, like \"2022-05-10\". On their green card.",
    "renewer.lpr_prior_status" => "For lawful permanent residents: the status they had before, if it's one of these; otherwise \"none\".",
    "renewer.armed_forces_connection" => "Whether they're an active-duty service member or honorably discharged veteran, or the spouse or child of one.",
    "renewer.lives_in_washington" => "Whether they live in Washington and plan to stay.",
    "renewer.has_ssn_or_applied_for_one" => "Whether they have a Social Security number or have applied for one.",
    "renewer.enrolled_in_ssi_foster_care_or_adoption_support_coverage" => "Whether they already get Apple Health through SSI, foster care, or adoption support.",
    "renewer.parent_or_caretaker_relative_of_dependent_child" => "Whether they're the parent or caretaker relative of a child who lives with them and depends on them.",

    # household_members
    "household_members" => "Other people who might be in their household for Apple Health. Include everyone they live with, and anyone who claims them as a tax dependent or whom that person claims, even if they live elsewhere. [] means nobody else. Leave this out until you've asked.",
    "household_members[]" => "One person, described in relation to the renewer.",
    "household_members[].relationship_to_renewer" => "How this person is related to the renewer.",
    "household_members[].lives_with_renewer" => "Whether this person lives with the renewer.",
    "household_members[].age" => "This person's age in years.",
    "household_members[].claimed_as_dependent_by_renewer" => "Whether the renewer expects to claim this person as a tax dependent.",
    "household_members[].claims_renewer_as_dependent" => "Whether this person expects to claim the renewer as a tax dependent.",
    "household_members[].lives_with_renewers_claimer_as_spouse" => "Whether this person is married to and lives with whoever claims the renewer as a tax dependent.",
    "household_members[].claimed_by_renewers_claimer" => "Whether whoever claims the renewer as a tax dependent also claims this person.",
    "household_members[].pregnant" => "Whether this person is pregnant now.",
    "household_members[].expected_unborn_children" => "If pregnant, how many babies they're expecting.",
    "household_members[].required_to_file_taxes" => "For a child or tax dependent: whether their own income is high enough that they're required to file a tax return.",

    # months
    "months" => "Income and activities, one entry per month. Needs the renewal month (for the income limit) and each of the 6 months before it (for the work requirement). Leave this out until you have at least one month.",
    "months[]" => "One month.",
    "months[].month" => "Which month, like \"2027-01\".",
    "months[].income_items" => "Each source of income anyone in the household had that month. [] means no income.",
    "months[].income_items[]" => "One source of income.",
    "months[].income_items[].household_member" => "Whose income it is: the index of the person in household_members. Leave out for the renewer's own income.",
    "months[].income_items[].type" => "What kind of income. Use educational_benefit_for_education_expenses for grants, loans, and scholarships spent on school; scholarship_for_living_expenses when spent on living costs.",
    "months[].income_items[].amount_cents" => "The amount before taxes, in cents, as paid at the frequency given. Net earnings for self-employment.",
    "months[].income_items[].frequency" => "How often it's paid. one_time for a single payment or lump sum that month.",
    "months[].work_hours" => "Hours the renewer worked that month, paid or unpaid, including work in exchange for things like rent.",
    "months[].doesnt_know_work_hours" => "true if the renewer can't say how many hours they worked. Then hours are worked out from their pay.",
    "months[].work_program_hours" => "Hours in a job training or work program that month.",
    "months[].community_service_hours" => "Hours of community service that month, with a structured program like a food bank, school, or library. Court-ordered counts; political activity doesn't.",
    "months[].in_education_program" => "Whether the renewer was enrolled in school or a training program that month.",
    "months[].enrolled_at_least_half_time" => "If in school: whether their school considers them at least half-time.",
    "months[].school_uses_credit_hours" => "If in school less than half-time: whether the school uses credit hours.",
    "months[].credit_hours" => "If in school less than half-time and the school uses credits: how many credit hours, 0 to 6.",
    "months[].education_program_hours" => "If in school less than half-time and the school doesn't use credits: hours in class or other school activities that month.",

    # work_requirement
    "work_requirement" => "Exclusions and exemptions from the work requirement. Each one means \"in any of the 6 months before renewal.\" Always send, as {} if nothing is known.",
    "work_requirement.is_american_indian_alaska_native" => "Whether they're American Indian or Alaska Native.",
    "work_requirement.is_former_foster_youth" => "Whether they were in foster care.",
    "work_requirement.within_12_months_postpartum" => "Whether they gave birth or had a pregnancy end within the last 12 months.",
    "work_requirement.cares_for_child_under_14" => "Whether they're a parent, guardian, or caretaker of a child 13 or younger.",
    "work_requirement.cares_for_person_with_disability" => "Whether they're a parent, guardian, caretaker, or family caregiver of someone with a disability.",
    "work_requirement.is_veteran_with_total_disability" => "Whether they're a veteran with a total (100%) disability rating, or paid at the 100% rate.",
    "work_requirement.is_medically_frail" => "Whether a disability or health condition makes it very hard for them to work: for example a substance use disorder, a serious mental illness, a condition that limits daily activities, or blindness.",
    "work_requirement.meets_snap_work_requirements" => "Whether they get Basic Food (SNAP), have to meet its work requirements, and are meeting them. Just getting Basic Food isn't enough.",
    "work_requirement.complies_with_tanf_work_requirements" => "Whether they get TANF cash assistance and are meeting its work requirements.",
    "work_requirement.in_drug_or_alcohol_treatment" => "Whether they're in a drug or alcohol treatment program.",
    "work_requirement.incarcerated_or_released_within_3_months" => "Whether they're in jail or prison, or were released within the last 3 months.",
    "work_requirement.enrolled_in_other_apple_health_program" => "Whether they're in an Apple Health program other than Apple Health for Adults.",
    "work_requirement.hardship_inpatient_care" => "Whether they spent time in a hospital, nursing home, or inpatient psychiatric care.",
    "work_requirement.hardship_travel_for_medical_care" => "Whether they had to travel more than an hour from home for medical care for a serious condition, for themselves or a dependent.",
    "work_requirement.hardship_disaster_area" => "Whether they live in a county under a federal disaster declaration.",
    "work_requirement.hardship_high_unemployment_county" => "Whether they live in a county with very high unemployment. The state decides this; usually leave it out unless they've been told.",
    "work_requirement.is_seasonal_worker" => "Whether their work is seasonal, like farm work in a growing season or retail work only during the holidays."
  }.freeze
end

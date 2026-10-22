# frozen_string_literal: true

# What the renewer tells us about themselves. Other modules build on these.
module RenewerFacts
  extend ActiveSupport::Concern

  included do
    in_module :renewer do
      # The month coverage renews, like "2027-03".
      fact :renewal_month do
        input [:renewer, :renewal_month], value: :string, format?: /\A\d{4}-(0[1-9]|1[0-2])\z/
      end

      fact :age do
        input [:renewer, :age], value: :integer, gteq?: 0
      end

      fact :under_19 do
        dependency :age
        proc { data[:dependencies][:age] < 19 }
      end

      fact :pregnant do
        input [:renewer, :pregnant], value: :bool?
      end

      fact :has_medicare do
        input [:renewer, :has_medicare], value: :bool?
      end

      fact :expected_unborn_children do
        input [:renewer, :expected_unborn_children], value: :integer, gteq?: 1
      end

      # Taxes, for the household rules (WAC 182-506-0012) and whose income counts (WAC 182-509-0360).
      fact :expects_to_file_taxes do
        input [:renewer, :expects_to_file_taxes], value: :bool?
      end

      fact :expects_to_be_claimed_as_dependent do
        input [:renewer, :expects_to_be_claimed_as_dependent], value: :bool?
      end

      # Including a stepparent or adoptive parent.
      fact :claimed_by_parent do
        input [:renewer, :claimed_by_parent], value: :bool?
      end

      fact :claimed_by_noncustodial_parent do
        input [:renewer, :claimed_by_noncustodial_parent], value: :bool?
      end

      fact :lives_with_both_parents do
        input [:renewer, :lives_with_both_parents], value: :bool?
      end

      fact :parents_file_jointly do
        input [:renewer, :parents_file_jointly], value: :bool?
      end

      # A shortcut: the person tells us, rather than us encoding the IRS filing thresholds.
      fact :required_to_file_taxes do
        input [:renewer, :required_to_file_taxes], value: :bool?
      end

      # In a medical institution, IMD, or inpatient psychiatric facility for 30 days in a row, or
      # likely to be (WAC 182-506-0010(3)).
      fact :in_medical_institution_30_days do
        input [:renewer, :in_medical_institution_30_days], value: :bool?
      end
    end
  end
end

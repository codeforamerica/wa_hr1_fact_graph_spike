# frozen_string_literal: true

module WaHr1
  # Arithmetic on ISO months ("2027-03") and dates ("2022-05-10").
  module Months
    module_function

    def index(month_or_date)
      year, month = month_or_date.split("-").first(2).map(&:to_i)
      year * 12 + month - 1
    end

    def from_index(index)
      year, month = index.divmod(12)
      format("%04d-%02d", year, month + 1)
    end

    # The `count` months before `month`, oldest first.
    def before(month, count)
      count.downto(1).map { |back| from_index(index(month) - back) }
    end
  end
end

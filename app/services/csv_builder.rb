# Minimal RFC-4180 writer shared by every admin CSV export (Ruby 4 dropped
# csv from the default gems, so the exports hand-roll their lines).
#
# Formula/CSV-injection guard: a cell whose raw text starts with =, +, -, @,
# TAB or CR is executed as a formula by spreadsheet apps. Such values get a
# leading single quote BEFORE quoting, so Excel/Sheets treat them as text.
class CsvBuilder
  FORMULA_PREFIX = /\A[=+\-@\t\r]/.freeze

  def self.line(fields)
    fields.map { |field| field(field) }.join(",")
  end

  def self.field(value)
    string = value.to_s
    string = "'#{string}" if string.match?(FORMULA_PREFIX)
    return string unless string.match?(/[",\n\r]/)

    %("#{string.gsub('"', '""')}")
  end
end

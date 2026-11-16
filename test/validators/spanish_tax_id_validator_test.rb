require "test_helper"

class SpanishTaxIdValidatorTest < ActiveSupport::TestCase
  # Real-world vectors (published AEAT examples and checksum-derived ones).
  VALID = %w[
    12345678Z 56746566T 00080902B
    X0471969D Y7789182Q Z5109432X
    A58818501 G02377372 C16567687 P0200000H
  ].freeze

  INVALID = [
    "12345678A", # wrong NIF letter
    "1234567",   # too short
    "123456789", # no control character
    "X0471969A", # wrong NIE letter
    "A5881850A", # A-class CIF needs a digit, not a letter
    "C16567677", # wrong CIF checksum
    "Ñ1234567A", # non-Latin prefix
    "12345678Z0" # too long
  ].freeze

  test "accepts valid NIF, NIE and CIF identifiers" do
    VALID.each { |id| assert SpanishTaxIdValidator.valid?(id), "#{id} should be valid" }
  end

  test "rejects malformed or bad-checksum identifiers" do
    INVALID.each { |id| refute SpanishTaxIdValidator.valid?(id), "#{id} should be invalid" }
  end

  test "is case and separator insensitive" do
    assert SpanishTaxIdValidator.valid?("12345678z")
    assert SpanishTaxIdValidator.valid?(" g02377372 ")
    assert SpanishTaxIdValidator.valid?("P0-200-000H")
  end

  test "blank values are skipped by the model integration, not rejected" do
    store = Store.new(user: users(:one), name: "Vat Tester #{SecureRandom.hex(4)}", store_type: :individual)
    store.vat_number = ""
    assert store.valid?, store.errors.full_messages.join(", ")

    store.vat_number = "12345678Z"
    assert store.valid?, store.errors.full_messages.join(", ")

    store.vat_number = "12345678A"
    refute store.valid?
    assert_includes store.errors[:vat_number], I18n.t("activerecord.errors.messages.spanish_tax_id_invalid")
  end
end

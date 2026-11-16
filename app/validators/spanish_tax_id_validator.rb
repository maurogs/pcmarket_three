# Validates Spanish tax identifiers on all three shapes:
#
#   NIF  — natural persons: 8 digits + control letter, computed as
#          "TRWAGMYFPDXBNJZSQVHLCKE"[digits % 23] (Real Decreto 1553/2005).
#   NIE  — foreigners: X/Y/Z + 7 digits + control letter, same algorithm
#          after substituting X→0, Y→1, Z→2.
#   CIF  — legal entities: type letter + 7-digit sequential + control char.
#          Control = (10 − units(2×d1 + 2×d3 + 2×d5 + 2×d7 digit-sums
#          + d2 + d4 + d6)) mod 10; a digit for A/B/E/H, a letter
#          (J=0 … I=9) for K/P/Q/S/W, either for the rest.
#
# Usage: `validates_with SpanishTaxIdValidator, attributes: %i[vat_number]`.
# Blank values are skipped (pair with `validates presence:` where required);
# surrounding spaces and hyphens are ignored, letters may be lowercase.
class SpanishTaxIdValidator < ActiveModel::Validator
  NIF_LETTERS = "TRWAGMYFPDXBNJZSQVHLCKE"
  CIF_LETTERS = "JABCDEFGHI"
  NIE_PREFIX = { "X" => "0", "Y" => "1", "Z" => "2" }.freeze
  # Entity kinds by control-character kind: digit, letter, or either.
  CIF_DIGIT_PREFIXES = %w[A B E H].freeze
  CIF_LETTER_PREFIXES = %w[K P Q S W].freeze
  CIF_ANY_PREFIXES = %w[C D F G I J L M N R T U V].freeze

  def self.valid?(raw)
    id = raw.to_s.strip.upcase.delete(" -")
    return false unless id.length == 9

    case id
    when /\A\d{8}[A-Z]\z/
      nif_control(id[0, 8]) == id[8]
    when /\A[XYZ]\d{7}[A-Z]\z/
      nif_control(NIE_PREFIX.fetch(id[0]) + id[1, 7]) == id[8]
    when /\A[A-Z]\d{7}[0-9A-Z]\z/
      cif_valid?(id)
    else
      false
    end
  end

  def self.nif_control(digits)
    NIF_LETTERS[digits.to_i % 23]
  end

  # Control digit for a CIF sequential number (7 digits, d1..d7): positions
  # 1/3/5/7 doubled with their digits summed, positions 2/4/6 added as-is.
  def self.cif_control(body)
    digits = body.chars.map(&:to_i)
    doubled = digits.each_with_index.sum do |digit, index|
      next 0 unless index.even?

      product = digit * 2
      product / 10 + product % 10
    end
    plain = digits.each_with_index.sum { |digit, index| index.odd? ? digit : 0 }
    (10 - (doubled + plain) % 10) % 10
  end

  def self.cif_valid?(id)
    prefix = id[0]
    return false unless (CIF_DIGIT_PREFIXES + CIF_LETTER_PREFIXES + CIF_ANY_PREFIXES).include?(prefix)

    control = cif_control(id[1, 7])
    case prefix
    when *CIF_DIGIT_PREFIXES then id[8] == control.to_s
    when *CIF_LETTER_PREFIXES then id[8] == CIF_LETTERS[control]
    else id[8] == control.to_s || id[8] == CIF_LETTERS[control]
    end
  end

  def validate(record)
    Array(options[:attributes]).each do |attribute|
      value = record.public_send(attribute)
      next if value.blank?
      next if self.class.valid?(value)

      record.errors.add(attribute, :spanish_tax_id_invalid)
    end
  end
end

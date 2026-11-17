require "test_helper"

# Contact-form rows (Phase 7b). Deliberately lightweight, but every field is
# bounded and the locale must be one the app actually ships.
class ContactMessageTest < ActiveSupport::TestCase
  def attrs(overrides = {})
    { name: "Ana López", email: "ana@example.com", subject: "Order question",
      body: "Where is my parcel, tracking says stuck.", locale: "en" }.merge(overrides)
  end

  test "a complete submission is valid" do
    assert_predicate ContactMessage.new(attrs), :valid?
  end

  test "name, subject and body are presence- and length-checked" do
    assert_not ContactMessage.new(attrs(name: "")).valid?
    assert_not ContactMessage.new(attrs(name: "A")).valid?
    assert_not ContactMessage.new(attrs(subject: "")).valid?
    assert_not ContactMessage.new(attrs(body: "too short")).valid?
    assert_not ContactMessage.new(attrs(body: "x" * 5_001)).valid?
  end

  test "the e-mail must look like an e-mail" do
    assert_not ContactMessage.new(attrs(email: "nope")).valid?
    assert_not ContactMessage.new(attrs(email: "")).valid?
  end

  test "the locale must be one of the shipped locales" do
    assert_not ContactMessage.new(attrs(locale: "cy")).valid?
    assert ContactMessage.new(attrs(locale: "pt")).valid?
  end
end

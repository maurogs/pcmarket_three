require "test_helper"

# CsvBuilder is the hand-rolled RFC-4180 writer behind every admin CSV
# export. Two contracts: spreadsheet formula-injection guard (leading `'`
# before quoting) and RFC-4180 quoting for ordinary text.
class CsvBuilderTest < ActiveSupport::TestCase
  test "formula-prefixed cells get the leading apostrophe guard" do
    {
      "=SUM(1+1)" => "'=SUM(1+1)",
      "+1+1" => "'+1+1",
      "-1+1" => "'-1+1",
      "@SUM(A1)" => "'@SUM(A1)",
      "\tTAB-PREFIX" => "'\tTAB-PREFIX",
      "\rCR-PREFIX" => "\"'\rCR-PREFIX\"" # CR also forces RFC-4180 quoting
    }.each do |raw, expected|
      assert_equal expected, CsvBuilder.field(raw), "guard failed for #{raw.inspect}"
    end
  end

  test "formula guard applies inside a full line" do
    line = CsvBuilder.line([ 4, "=HYPERLINK(\"http://evil\")", "ok" ])
    assert_equal %q{4,"'=HYPERLINK(""http://evil"")",ok}, line
  end

  test "guard is applied before quoting, so commas still force quoting" do
    assert_equal %q("'=1,2"), CsvBuilder.field("=1,2")
  end

  test "ordinary cells are emitted unguarded" do
    assert_equal "plain text", CsvBuilder.field("plain text")
    assert_equal "Gigabyte RTX 4070", CsvBuilder.field("Gigabyte RTX 4070")
    assert_equal "42", CsvBuilder.field(42)
    timestamp = Time.zone.parse("2026-11-17T10:00:00Z").iso8601
    assert_equal timestamp, CsvBuilder.field(timestamp)
    # Hyphens/at-signs mid-string are not formula starts.
    assert_equal "e-mail @ work", CsvBuilder.field("e-mail @ work")
  end

  test "only a leading - is guarded, not an embedded one" do
    assert_equal "'-5", CsvBuilder.field("-5") # leading minus is guarded by design
    assert_equal "12-5", CsvBuilder.field("12-5")
  end

  test "rfc4180 quoting for commas, quotes and newlines" do
    assert_equal %q("a,b"), CsvBuilder.field("a,b")
    assert_equal %q("say ""hi"""), CsvBuilder.field(%q(say "hi"))
    assert_equal %Q("two\nlines"), CsvBuilder.field("two\nlines")
  end

  test "a full line joins fields with commas" do
    assert_equal "1,Gigabyte RTX,59999,EUR", CsvBuilder.line([ 1, "Gigabyte RTX", 59999, "EUR" ])
    assert_equal "id,title", CsvBuilder.line(%w[id title])
  end

  test "nil and empty cells render as empty fields" do
    assert_equal ",", CsvBuilder.line([ nil, "" ])
  end
end

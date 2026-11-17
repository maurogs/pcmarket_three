require "test_helper"

# The demo seed stores provider credits in blob metadata; the public gallery
# must render them under each photo (ListingsHelper#photo_credit_tag).
class ListingPhotoCreditTest < ActionDispatch::IntegrationTest
  test "the gallery shows the attribution credit for a seeded photo" do
    listing = listings(:as_new)
    attach_photo(listing, "demo-photo.jpg", "image/jpeg", attribution: {
                   "creator" => "Anne Artist", "creator_url" => "https://example.com/anne",
                   "license" => "BY-SA 4.0", "license_url" => "https://creativecommons.org/licenses/by-sa/4.0",
                   "source_url" => "https://flickr.example.com/photos/1", "provider" => "openverse"
                 })

    get listing_path(listing)

    assert_response :success
    assert_select "span > a[href=?]", "https://flickr.example.com/photos/1",
                  text: "Photo: Anne Artist · BY-SA 4.0 via Openverse"
  end

  test "no credit line is rendered for photos without attribution" do
    listing = listings(:gigabyte)
    attach_photo(listing, "plain.png", "image/png")

    get listing_path(listing)

    assert_response :success
    assert_not response.body.include?("Photo:")
  end

  private

  # Blobs are created with identify: false + explicit dimensions, exactly how
  # the demo seed attaches them (the gallery helper needs width/height).
  def attach_photo(listing, filename, content_type, attribution: nil)
    header = content_type == "image/jpeg" ? "\xFF\xD8\xFF".b : "\x89PNG\r\n\x1A\n".b
    metadata = { "identified" => true, "width" => 1200, "height" => 800 }
    metadata["attribution"] = attribution if attribution

    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new((header + ("x" * 64)).b),
      filename:, content_type:, identify: false, metadata:
    )
    listing.photos.attach(blob)
  end
end

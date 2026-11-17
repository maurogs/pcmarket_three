require "test_helper"

module Api
  module V1
    # The seller area: everything is looked up through current_user.listings,
    # so foreign ids 404, and state changes stay in the nested resources
    # (submission / archival / sale_mark) exactly like the web forms.
    class SellTest < ActionDispatch::IntegrationTest
      setup do
        @seller = users(:one)
      end

      test "the dashboard reports counts, revenue and the store" do
        get_json "/api/v1/sell/dashboard", auth_as: @seller

        assert_response :ok
        dashboard = json_body[:dashboard]
        assert dashboard[:listings].is_a?(Hash)
        assert dashboard[:listings].key?(:approved)
        assert_not dashboard[:revenue_money].nil?
        assert dashboard[:orders].is_a?(Hash)
        assert_not dashboard[:store].nil?
      end

      test "the seller sees their own listings in every state, filtered by status" do
        get_json "/api/v1/sell/listings", auth_as: @seller

        assert_response :ok
        slugs = json_body[:listings].map { |l| l[:slug] }
        assert_includes slugs, listings(:gigabyte).slug
        assert_includes slugs, listings(:pending).slug, "moderation states must be visible to their owner"
        assert_not_includes slugs, listings(:as_new).slug

        get_json "/api/v1/sell/listings?status=draft", auth_as: users(:two)
        assert_response :ok
        assert_equal [ listings(:draft).slug ], json_body[:listings].map { |l| l[:slug] }
      end

      test "someone else's listing is a 404 even by slug" do
        get_json "/api/v1/sell/listings/#{listings(:as_new).slug}", auth_as: @seller

        assert_response :not_found
        assert_equal "not_found", json_body.dig(:error, :code)
      end

      test "creating a listing saves a draft and submission queues it" do
        payload = {
          title: "Ryzen mid tower build",
          description: "Upgraded cooler, always run on a UPS.",
          condition: "used_good",
          price: "249.99",
          quantity: 1,
          category_root: "gaming-pcs",
          category_child: "gaming-desktops",
          specs: { gpu_model: "RTX 3060", cpu_model: "Ryzen 5 5600" },
          city: "Madrid"
        }

        post_json "/api/v1/sell/listings", payload, auth_as: @seller
        assert_response :created
        listing = json_body[:listing]
        assert_equal "draft", listing[:status]
        assert_equal "€249.99", listing.dig(:price_money, :formatted)
        slug = listing[:slug]

        post_json "/api/v1/sell/listings/#{slug}/submission", {}, auth_as: @seller
        assert_response :ok
        assert_equal "pending_review", json_body.dig(:listing, :status)
        assert_not json_body[:message].blank?

        # A second submission is not a legal transition.
        post_json "/api/v1/sell/listings/#{slug}/submission", {}, auth_as: @seller
        assert_response :conflict
      end

      test "a direct-uploaded photo rides the draft into submission" do
        bytes = "fake-jpeg-bytes"
        post_json "/api/v1/direct_uploads", {
          blob: {
            filename: "gpu.jpg", byte_size: bytes.bytesize, content_type: "image/jpeg",
            checksum: Base64.strict_encode64(Digest::MD5.digest(bytes)), metadata: {}
          }
        }, auth_as: @seller
        assert_response :created
        upload = json_body
        signed_id = upload[:signed_id]
        assert_not signed_id.blank?

        # The client is responsible for pushing the bytes: the returned URL
        # is a signed disk-service route and the returned headers are what
        # it validates (checksum, byte size, content type).
        put upload.dig(:direct_upload, :url),
            params: bytes,
            headers: upload.dig(:direct_upload, :headers)
        assert_response :no_content

        post_json "/api/v1/sell/listings", {
          title: "RTX 3060 build with receipts",
          description: "Invoice from the shop, still under warranty.",
          condition: "used_good",
          price: "199.99",
          quantity: 1,
          category_root: "gaming-pcs",
          category_child: "gaming-desktops",
          city: "Barcelona",
          specs: { gpu_model: "RTX 3060", cpu_model: "Ryzen 5 5600" },
          photos: [ signed_id ]
        }, auth_as: @seller
        assert_response :created
        listing = json_body[:listing]
        assert_equal "draft", listing[:status]
        assert_equal 1, listing[:photos].size
        assert listing.dig(:photos, 0, :card).present?

        post_json "/api/v1/sell/listings/#{listing[:slug]}/submission", {}, auth_as: @seller
        assert_response :ok
        assert_equal "pending_review", json_body.dig(:listing, :status)
      end

      test "an invalid listing returns the model's messages" do
        post_json "/api/v1/sell/listings", { title: "no" }, auth_as: @seller

        assert_response :unprocessable_entity
        assert_equal "invalid_request", json_body.dig(:error, :code)
        assert_not json_body.dig(:error, :details).blank?
      end

      test "archiving needs the owner and a legal state" do
        listing = listings(:gigabyte) # approved, owned by @seller

        post_json "/api/v1/sell/listings/#{listing.slug}/archival", {}, auth_as: users(:admin)
        assert_response :not_found

        post_json "/api/v1/sell/listings/#{listing.slug}/archival", {}, auth_as: @seller
        assert_response :ok
        assert_equal "archived", json_body.dig(:listing, :status)

        post_json "/api/v1/sell/listings/#{listing.slug}/archival", {}, auth_as: @seller
        assert_response :conflict
      end

      test "mark-sold moves an approved listing to sold" do
        post_json "/api/v1/sell/listings/#{listings(:as_new).slug}/sale_mark", {}, auth_as: users(:two)

        assert_response :ok
        assert_equal "sold", json_body.dig(:listing, :status)
      end
    end
  end
end

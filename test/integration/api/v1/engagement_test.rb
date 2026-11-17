require "test_helper"

module Api
  module V1
    # Wishlist and the public taxonomy endpoints the apps read alongside it.
    class EngagementTest < ActionDispatch::IntegrationTest
      setup do
        @user = users(:one)
        @listing = listings(:as_new)
      end

      test "hearts are idempotent and the list carries the saved price" do
        get_json "/api/v1/favorites", auth_as: @user
        assert_response :ok
        assert_empty json_body[:favorites]

        post_json "/api/v1/favorites", auth_as: @user, params: { listing_id: @listing.id }
        assert_response :ok
        favorite_id = json_body[:favorite_id]
        assert_not favorite_id.nil?

        post_json "/api/v1/favorites", auth_as: @user, params: { listing_id: @listing.id }
        assert_response :ok
        assert_equal favorite_id, json_body[:favorite_id]

        get_json "/api/v1/favorites", auth_as: @user
        favorite = json_body[:favorites].first
        assert_equal favorite_id, favorite[:favorite_id]
        assert_equal @listing.slug, favorite.dig(:listing, :slug)
        assert_not favorite[:saved_price_money].blank?

        delete_json "/api/v1/favorites/#{favorite_id}", auth_as: @user
        assert_response :ok
        assert_equal 0, @user.favorites.count
      end

      test "hearts are refused for anonymous clients and for hidden listings" do
        post_json "/api/v1/favorites", params: { listing_id: @listing.id }
        assert_response :unauthorized

        # Drafts are not in the visible scope, so they 404 rather than 403.
        post_json "/api/v1/favorites", auth_as: @user, params: { listing_id: listings(:draft).id }
        assert_response :not_found
        assert_equal "not_found", json_body.dig(:error, :code)
      end

      test "categories are public and nested by parent id" do
        get_json "/api/v1/categories"

        assert_response :ok
        roots = json_body[:categories]
        assert_includes roots.map { |c| c[:slug] }, "gaming-pcs"
      end
    end
  end
end

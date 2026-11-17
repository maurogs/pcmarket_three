require "test_helper"

class Admin::ReviewsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:admin)
  end

  test "admin sees the reviews index" do
    review = build_review(order: create_order(1), rating: 5, body: "FAST SHIPPING REVIEW")

    get admin_reviews_path
    assert_response :ok
    assert_includes response.body, "FAST SHIPPING REVIEW"
    assert_includes response.body, review.store.name
  end

  test "non-admin gets 404" do
    sign_in_as users(:one)

    get admin_reviews_path
    assert_response :not_found
  end

  test "destroy hides the review, audits it and recomputes the store rating" do
    store = stores(:one)
    hidden_review = build_review(order: create_order(1), rating: 5, store: store, body: "FIVE STAR REVIEW")
    kept_review = build_review(order: create_order(2), rating: 3, store: store, body: "THREE STAR REVIEW")
    assert_equal 2, store.reload.reviews_count
    assert_in_delta 4.0, store.rating_average

    assert_no_difference "Review.count" do
      assert_difference -> { AdminAuditLog.count }, 1 do
        delete admin_review_path(hidden_review), params: { reason: "Abusive language" }
      end
    end
    assert_redirected_to admin_reviews_path
    assert_equal "Review hidden", flash[:notice]

    hidden_review.reload
    assert_not_nil hidden_review.hidden_at
    assert_predicate hidden_review, :hidden?

    audit = AdminAuditLog.find_by(action: "review_hide", subject: hidden_review)
    assert_equal "Abusive language", audit.details["reason"]
    assert_equal 5, audit.details["rating"]

    store.reload
    assert_equal 1, store.reviews_count
    assert_in_delta 3.0, store.rating_average
  end

  test "hiding without a reason is refused" do
    review = build_review(order: create_order(1), rating: 4)
    store = review.store
    before_average = store.reload.rating_average

    assert_no_difference "AdminAuditLog.count" do
      delete admin_review_path(review), params: { reason: "   " }
    end
    assert_redirected_to admin_reviews_path
    assert_not flash[:alert].blank?

    review.reload
    assert_nil review.hidden_at
    assert_not_predicate review, :hidden?
    assert_in_delta before_average, store.reload.rating_average
  end

  test "hidden reviews drop out of the visible list but stay under the hidden filter" do
    review = build_review(order: create_order(1), rating: 1, body: "SPAM CONTENT REVIEW")

    delete admin_review_path(review), params: { reason: "Spam" }
    assert_response :redirect

    get admin_reviews_path(state: "visible")
    assert_response :ok
    assert_no_match(/SPAM CONTENT REVIEW/, response.body)

    get admin_reviews_path(state: "hidden")
    assert_response :ok
    assert_includes response.body, "SPAM CONTENT REVIEW"

    # Default index still lists it (as an auditable record) but without a hide form.
    get admin_reviews_path
    assert_includes response.body, "SPAM CONTENT REVIEW"
    assert_no_match(%r{<form[^>]*action="#{Regexp.escape(admin_review_path(review))}"}, response.body)
  end

  private

  def create_order(sequence)
    Order.create!(number: "PCM-2025-9991#{sequence}0", buyer: users(:two), seller: users(:one),
                  status: :completed, subtotal_cents: 10_000, total_cents: 10_000)
  end

  # Reviews need an order (one per review); they hang off stores(:one) so the
  # cached rating callbacks have a target to refresh.
  def build_review(order:, rating:, store: stores(:one), body: nil)
    Review.create!(order: order, reviewer: users(:two), store: store,
                   seller: store.user, rating: rating, body: body)
  end
end

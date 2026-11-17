require "test_helper"

class ReviewTest < ActiveSupport::TestCase
  test "creating a review refreshes the store rating" do
    store = stores(:two)
    assert_equal 0, store.rating_average.to_i

    Review.create!(order: orders(:one), reviewer: users(:one), store: store, seller: users(:two), rating: 4)
    store.reload
    assert_equal 4.0, store.rating_average
    assert_equal 1, store.reviews_count
  end

  test "destroying a review refreshes the store rating" do
    store = stores(:one)
    review = Review.create!(order: orders(:two), reviewer: users(:two), store: store, seller: users(:one), rating: 5)
    assert_equal 5.0, store.reload.rating_average

    review.destroy
    assert_equal 0.0, store.reload.rating_average
    assert_equal 0, store.reviews_count
  end

  test "destroying an order destroys its review" do
    review = Review.create!(order: orders(:one), reviewer: users(:one), store: stores(:two), seller: users(:two), rating: 4)

    orders(:one).destroy

    assert_nil Review.find_by(id: review.id)
  end

  test "one review per order" do
    Review.create!(order: orders(:one), reviewer: users(:one), store: stores(:two), rating: 4)
    other = Review.new(order: orders(:one), reviewer: users(:one), store: stores(:two), rating: 2)
    assert_not other.valid?
    assert_includes other.errors[:order_id], "has already been taken"
  end

  test "rating must be between one and five" do
    review = Review.new(order: orders(:one), reviewer: users(:one), store: stores(:two), rating: 6)
    assert_not review.valid?
    assert_includes review.errors[:rating], "must be in 1..5"
  end
end

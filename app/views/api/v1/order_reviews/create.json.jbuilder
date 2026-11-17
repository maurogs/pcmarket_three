json.review do
  json.id @review.id
  json.rating @review.rating
  json.body @review.body
  json.author do
    json.id @review.reviewer.id
    json.display_name @review.reviewer.display_name
  end
  json.created_at @review.created_at.utc.iso8601
end
json.message t("api.order_reviews.created")

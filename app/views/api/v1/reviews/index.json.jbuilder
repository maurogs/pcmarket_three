json.reviews @reviews do |review|
  json.id review.id
  json.rating review.rating
  json.body review.body
  json.author do
    json.id review.reviewer.id
    json.display_name review.reviewer.display_name
  end
  json.created_at review.created_at.utc.iso8601
end
json.meta do
  json.pagination pagination_meta(@pagy)
end

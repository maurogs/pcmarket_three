json.id offer.id
if offer.listing
  json.listing do
    json.id offer.listing.id
    json.slug offer.listing.slug
    json.title offer.listing.title
  end
end
json.buyer { json.id offer.buyer.id; json.display_name offer.buyer.display_name }
json.seller { json.id offer.seller.id; json.display_name offer.seller.display_name }
json.amount_money money_json(Money.new(offer.amount_cents, offer.listing.currency))
json.asking_money money_json(Money.new(offer.listing.price_cents, offer.listing.currency))
json.status offer.status
json.expires_at offer.expires_at&.utc&.iso8601
json.created_at offer.created_at.utc.iso8601
json.updated_at offer.updated_at.utc.iso8601

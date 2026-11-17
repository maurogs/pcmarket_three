# frozen_string_literal: true

# PHASE 9 — realistic Spanish demo data (development only, or SEED_DEMO=1).
#
# Builds a full demo marketplace: an admin, individual sellers with stores,
# verified business stores (valid CIFs, logos, banners, policies), buyers,
# and a weighted catalogue of listings across every leaf category, with real
# photos fetched through DemoImages::Fetcher (Openverse / Pexels / Pixabay)
# and generated placeholders when offline. Favourites, follows, saved
# searches, conversations, offers, orders in every lifecycle state, reviews,
# disputes, notifications, reports and contact messages complete the graph.
#
#   bin/rails db:seed                    # development, 300 listings
#   SEED_LISTINGS=20 bin/rails db:seed   # smaller run
#   SEED_RESET=1 bin/rails db:seed       # wipe demo records first
#
# Every demo user owns a fixed `*@demo.pcmarket.test` e-mail — the
# idempotency marker: a second run only tops up listings to the target and
# skips the social graph when demo favourites already exist. Refuses to run
# in production unless ALLOW_DEMO_SEED=1.
#
# This file defines DemoSeed without executing it; db/seeds.rb loads it and
# calls DemoSeed.run! under the environment gate. Tests require it directly.

module DemoSeed
  DEMO_DOMAIN = "demo.pcmarket.test"
  LEGACY_DOMAIN = "pcmarket.test"
  PASSWORD = "DemoPassw0rd!"
  DEFAULT_COUNT = 300

  PROVINCES = YAML.load_file(Rails.root.join("config/data/es_provinces.yml")).freeze

  # Store labels applied to store-owned listings of these category roots.
  LABEL_POOL = {
    "gaming-pcs" => %w[staff-pick featured],
    "gpus" => %w[staff-pick featured],
    "laptops" => %w[staff-pick featured],
    "workstations" => %w[staff-pick],
    "consoles" => %w[rare staff-pick]
  }.freeze

  BUSINESS_NAMES = [
    "InfoTech Madrid", "Componentes BCN", "GamerZone Valencia", "PC Bilbao Outlet",
    "TeknoSur Sevilla", "AlphaRigs Zaragoza", "RetroGame Coruña", "Nexus Informatica Málaga"
  ].freeze

  CITY_NAMES = {
    "Madrid" => "Madrid", "Barcelona" => "Barcelona", "Valencia" => "Valencia",
    "Sevilla" => "Sevilla", "Zaragoza" => "Zaragoza", "Murcia" => "Murcia",
    "Palma" => "Palma", "Las Palmas" => "Las Palmas de Gran Canaria",
    "Vizcaya" => "Bilbao", "A Coruña" => "A Coruña", "Asturias" => "Oviedo",
    "Gipuzkoa" => "San Sebastián", "Álava" => "Vitoria", "Cantabria" => "Santander"
  }.freeze

  POLICIES = {
    returns: "Devoluciones hasta 14 días naturales desde la recepción, en su embalaje original y " \
             "sin señales de uso. Los gastos de devolución corren a cargo del comprador salvo " \
             "producto defectuoso. Reembolso íntegro en 72 horas laborables.",
    shipping: "Envíos a península en 24-72 h por Correos, SEUR o MRW. Baleares y Canarias: 3-5 días " \
              "(pueden aplicarse recargos). Recogida en tienda gratuita con cita previa."
  }.freeze

  REJECTION_REASONS = [
    "Las fotos no se corresponden con el artículo anunciado.",
    "Falta el número de serie y no podemos verificar el estado del producto.",
    "Precio visiblemente por debajo de mercado: posible estafa.",
    "La descripción incluye datos de contacto personales.",
    "Categoría incorrecta: el artículo no corresponde a la selección."
  ].freeze

  CONDITION_BLURBS = {
    "brand_new" => "Producto precintado, con garantía oficial de dos años y factura. Se entrega en su embalaje de fábrica.",
    "open_box" => "Caja abierta únicamente para verificar el contenido; el producto está sin usar y completo con todos sus accesorios.",
    "used_like_new" => "Usado muy poco, en estado prácticamente de nuevo. Limpio, probado a fondo y funcionando perfectamente. Solo pequeñas marcas estéticas.",
    "used_good" => "Segunda mano en buen estado, con marcas de uso normales. Probado antes del anuncio: todo funciona como debe. Se vende tal cual se muestra en las fotos.",
    "for_parts" => "Vendido como pieza o para piezas: tiene la avería indicada en la descripción. Ideal para reaprovechar componentes o reparaciones caseras."
  }.freeze

  CONVERSATION_SCRIPTS = [
    [ "Hola, ¿sigue disponible?", "Sí, aún lo tengo. ¿Te interesa?",
     "¿Podrías bajar un poco el precio?", "Podría hacer un pequeño descuento si lo recojo en persona." ],
    [ "Buenas, ¿lo envías a Canarias?", "Sí, a Canarias por Correos, unos 4 o 5 días.",
     "Perfecto, ¿aceptas transferencia?", "Mejor por la plataforma, así el pago queda protegido." ],
    [ "¿Tiene garantía?", "Tres meses de garantía del vendedor en todos mis anuncios.",
     "Genial, lo cojo.", "¡Gracias! Te lo envío mañana mismo." ],
    [ "¿Está libre de mineros?", "Nunca se usó para minar, puedo enseñar los registros de temperatura.",
     "Qué bien. ¿Se puede ver en persona?", "Sí, sin problema, estoy por el centro." ],
    [ "Hola, ¿el envío incluye seguro?", "Todos los envíos salen asegurados por el importe completo.",
     "Genial, muchas gracias.", "A ti, cualquier duda me dices." ],
    [ "¿El RGB funciona bien?", "Perfecto, los controladores están actualizados y la iluminación va fina.",
     "¿Tiene los cables originales?", "Sí, caja y accesorios completos." ]
  ].freeze

  REVIEW_BLURBS = [
    "Todo perfecto, llegó antes de lo previsto y tal cual se describía.",
    "Vendedor muy amable, respondió rápido a todas las dudas.",
    "Producto tal y como en las fotos. Repetiré.",
    "Bien embalado y funciona de maravilla.",
    "Trato correcto, aunque tardó un día más de lo esperado.",
    "Calidad-precio inmejorable, muy contento con la compra.",
    "Atención de diez. El artículo venía mejor de lo que esperaba."
  ].freeze

  REPORT_DETAILS = [
    "El vendedor pide un adelanto por fuera y luego no responde.",
    "El anuncio dice 16 GB pero la foto del modelo es de 8 GB.",
    "Publica un artículo que no debería venderse en esta categoría.",
    "El enlace del anuncio lleva a una web externa de pago."
  ].freeze

  CONTACT_SUBJECTS = [
    "Duda con los comisiones", "Problema con un pedido", "Verificación de tienda",
    "Sugerencia de categoría", "No puedo editar mi anuncio", "Consulta sobre envíos"
  ].freeze

  class << self
    attr_reader :counts

    def run!(count: nil)
      unless runnable?
        puts "[demo seed] skipped (Rails env #{Rails.env}; set SEED_DEMO=1 to force; never in production without ALLOW_DEMO_SEED=1)"
        return
      end

      require "faker"

      @rng = Random.new(20_261_117)
      @counts = Hash.new(0)
      @fetcher = DemoImages::Fetcher.new
      Faker::Config.locale = "es"

      cleanup_legacy_samples!
      reset_demo! if ENV["SEED_RESET"] == "1"

      admin = seed_admin
      buyers = (1..60).map { |i| find_or_create_user("buyer#{i}") }
      sellers = (1..40).map { |i| find_or_create_user("seller#{i}") }
      stores = (1..8).map { |i| seed_business_store(i) }
      listings = seed_listings(count, admin, sellers, stores)
      seed_social_graph(admin, buyers, sellers, stores, listings)

      report
      { admin: admin, buyers: buyers, listings: listings }
    end

    private

    def runnable?
      # db/seeds.rb already gates the call (development, or SEED_DEMO=1);
      # this is the hard safety net: never production without an explicit
      # opt-in. Tests call DemoSeed.run! directly on purpose.
      return false if Rails.env.production? && ENV["ALLOW_DEMO_SEED"] != "1"

      true
    end

    def catalog
      @catalog ||= begin
        raw = YAML.load_file(Rails.root.join("db/seeds/data/demo_catalog.yml"))
        defaults = raw["defaults"] || {}
        raw.fetch("categories").transform_values { |entry| defaults.merge(entry) }
      end
    end

    def demo_users
      User.where("email_address LIKE ?", "%@#{DEMO_DOMAIN}")
    end

    # --- one-time removal of the pre-Phase-9 sample content -------------------
    def cleanup_legacy_samples!
      legacy = User.where("email_address LIKE ?", "%@#{LEGACY_DOMAIN}")
                   .where.not("email_address LIKE ?", "%@#{DEMO_DOMAIN}")
      return if legacy.none?

      puts "Removing #{legacy.count} legacy sample users (pre-Phase-9)..."
      legacy.find_each { |u| u.destroy! }
    end

    def reset_demo!
      puts "SEED_RESET=1: wiping demo records..."
      ids = demo_users.pluck(:id)
      store_ids = Store.where(user_id: ids).pluck(:id)
      listing_ids = Listing.where(user_id: ids).pluck(:id)
      conv_ids = Conversation.where(buyer_id: ids).or(Conversation.where(seller_id: ids)).pluck(:id)

      FriendlyId::Slug.where(sluggable_type: "Listing", sluggable_id: listing_ids).delete_all
      FriendlyId::Slug.where(sluggable_type: "Store", sluggable_id: store_ids).delete_all
      Review.where(store_id: store_ids).or(Review.where(reviewer_id: ids)).delete_all
      Message.where(conversation_id: conv_ids).delete_all
      Conversation.where(id: conv_ids).delete_all
      Offer.where(listing_id: listing_ids).delete_all
      Notification.where(user_id: ids).delete_all
      Favorite.where(user_id: ids).or(Favorite.where(listing_id: listing_ids)).delete_all
      Follow.where(follower_id: ids).or(Follow.where(store_id: store_ids)).delete_all
      SavedSearch.where(user_id: ids).delete_all
      ModerationEvent.where(listing_id: listing_ids).delete_all
      Report.where(user_id: ids).or(Report.where(listing_id: listing_ids)).delete_all
      OrderItem.where(order_id: Order.where(buyer_id: ids).select(:id)).delete_all
      Order.where(buyer_id: ids).or(Order.where(seller_id: ids)).delete_all
      Listing.where(user_id: ids).destroy_all # destroys photo attachments too
      Store.where(user_id: ids).destroy_all
      User.where(id: ids).destroy_all
    end

    # --- people and stores ------------------------------------------------------
    def seed_admin
      find_or_create_user("admin", role: "admin", first_name: "Admin", last_name: "PCMarket")
    end

    def find_or_create_user(local, role: "user", first_name: nil, last_name: nil)
      email = "#{local}@#{DEMO_DOMAIN}"
      User.find_by(email_address: email) || User.create!(
        email_address: email,
        username: unique_username(local),
        first_name: first_name || Faker::Name.first_name,
        last_name: last_name || Faker::Name.last_name,
        password: PASSWORD,
        password_confirmation: PASSWORD,
        role: role,
        confirmed_at: Time.current
      ).tap { @counts["users"] += 1 }
    end

    def unique_username(local)
      candidate = local
      n = 0
      while User.exists?(username: candidate)
        n += 1
        candidate = "#{local}#{n}"
      end
      candidate
    end

    def seed_business_store(i)
      user = find_or_create_user("business#{i}")
      return Store.find_by(user: user) if Store.exists?(user: user)

      name = BUSINESS_NAMES[(i - 1) % BUSINESS_NAMES.size]
      city, region = sample_location
      store = Store.create!(
        user: user, name: name, slug: name.parameterize, store_type: "business",
        verified: true, vat_number: valid_cif, sales_count: rand(40..900),
        city: city, region: region, description: business_description(name),
        returns_policy: POLICIES[:returns], shipping_policy: POLICIES[:shipping],
        default_shipping_cents: [ 395, 495, 595, 695 ].sample(random: @rng),
        allow_offers_default: true
      )
      attach_store_images(store, name)
      @counts["stores"] += 1
      store
    end

    def seed_individual_store(user)
      return Store.find_by(user: user) if Store.exists?(user: user)

      city, region = sample_location
      base = "#{Faker::Commerce.vendor} #{user.last_name}".truncate(55, separator: " ")
      name = base
      n = 0
      while Store.exists?(name: name)
        n += 1
        name = "#{base} #{n}"
      end
      Store.create!(
        user: user, name: name, slug: name.parameterize, store_type: "individual",
        city: city, region: region, sales_count: rand(0..40),
        description: Faker::Lorem.sentence(word_count: rand(6..14)),
        allow_offers_default: @rng.rand < 0.7
      ).tap { @counts["stores"] += 1 }
    end

    def business_description(name)
      city, = sample_location
      "Tienda especializada en hardware y componentes de segunda mano y reacondicionados. " \
        "Más de 500 envíos completados con valoraciones positivas. Todos nuestros artículos " \
        "se prueban antes de publicarse. Punto de recogida en #{city}."
    end

    def sample_location
      province = PROVINCES[rand(PROVINCES.size)]
      city = CITY_NAMES[province["name"]] || province["name"]
      [ city, province["name"] ] # the region column holds the province name (EsProvince validator)
    end

    def valid_cif
      body = format("%07d", @rng.rand(1_000_000))
      "B#{body}#{SpanishTaxIdValidator.cif_control(body)}"
    end

    def attach_store_images(store, name)
      logo = DemoImages::Placeholder.render(
        title: name.split(/[ -]/).filter_map { |w| w[0] }.first(2).join.upcase,
        category_label: nil, path: Rails.root.join("tmp/demo_images/logos/#{store.slug}.png").to_s,
        seed: store.id
      )
      if logo
        File.open(logo, "rb") { |io| store.logo.attach(io: io, filename: "logo.png", content_type: "image/png") }
      end
      banner = DemoImages::Placeholder.render(
        title: name, category_label: nil, path: Rails.root.join("tmp/demo_images/banners/#{store.slug}.png").to_s,
        seed: store.id + 3
      )
      if banner
        File.open(banner, "rb") { |io| store.banner.attach(io: io, filename: "banner.png", content_type: "image/png") }
      end
    rescue StandardError => e
      warn "store images skipped for #{store.name}: #{e.class}: #{e.message}"
    end
    # --- listings ---------------------------------------------------------------
    def seed_listings(count, admin, sellers, stores)
      target = (count || ENV["SEED_LISTINGS"] || DEFAULT_COUNT).to_i
      existing = Listing.where(user: demo_users).count
      need = [ target - existing, 0 ].max
      puts "Demo listings: #{existing} existing, #{need} to create (target #{target})"
      return Listing.where(user: demo_users) if need.zero?

      leaves = Category.order(:id).select { |c| c.children.none? }
      # Fixture-only categories (test DB) have no catalog entry: weight 1.
      weighted = leaves.flat_map { |c| Array.new(((catalog[c.slug] || {})["weight"] || 1).to_i, c) }

      # Status mix allocated by counts, so even small runs get every state.
      shares = { approved: 0.70, pending_review: 0.10, rejected: 0.05, sold: 0.10, draft: 0.05 }
      counts_by_status = shares.transform_values { |s| (need * s).round }
      counts_by_status[:approved] += need - counts_by_status.values.sum
      statuses = counts_by_status.flat_map { |s, n| Array.new(n, s) }.shuffle(random: @rng)

      # Coverage first: one listing per uncovered leaf, then weighted random.
      covered = Listing.where(user: demo_users).group(:category_id).count
      plan = leaves.reject { |c| covered[c.id].to_i.positive? }.shuffle(random: @rng).first(need)
      plan += Array.new(need - plan.size) { weighted[rand(weighted.size)] }
      plan = plan.first(need)

      seller_stores = (sellers.map { |u| seed_individual_store(u) } + stores).compact
      created = 0
      skipped = {} # category slug => first validation error seen there
      plan.each_with_index do |leaf, idx|
        attrs = build_listing_attrs(leaf, sellers, seller_stores, statuses[idx])
        listing = Listing.new(attrs)
        unless listing.save
          error = listing.errors.full_messages.first
          skipped[leaf.slug] ||= error
          puts "  skip #{attrs[:title].truncate(40)}: #{listing.errors.full_messages.join(', ')}"
          next
        end
        finalize_listing(listing, attrs, admin)
        created += 1
        @counts["listings:#{attrs[:status]}"] += 1
      end
      unless skipped.empty?
        puts "Validation errors per category (fix the catalog, these listings were skipped):"
        skipped.each { |slug, error| puts "  #{slug}: #{error}" }
      end
      puts "Created #{created} demo listings (photo sources: #{@fetcher.source_counts})"
      Listing.where(user: demo_users)
    end

    def build_listing_attrs(leaf, sellers, seller_stores, status)
      entry = catalog[leaf.slug] || {} # fixture-only leaves (tests) have no entry
      models = entry["models"]
      model = models&.any? ? models[rand(models.size)] : nil
      title = model ? model[0] : generic_title(leaf)
      title += " (#{Faker::Lorem.word.capitalize})" if @rng.rand < 0.08
      title = title.truncate(120)

      store = @rng.rand < 0.45 ? seller_stores[rand(seller_stores.size)] : nil
      seller = store ? store.user : sellers[rand(sellers.size)]

      condition = weighted_condition
      new_range = (model && model[1..2]) || entry["new"] || [ 100, 400 ]
      used_range = (model && model[3..4]) || entry["used"] || [ 60, 260 ]
      cents = price_cents_for(condition, new_range, used_range)

      city, region = sample_location
      posted = rand(1..180).days.ago
      shipping = @rng.rand < 0.4 ? 0 : [ 295, 395, 495, 695, 895 ].sample(random: @rng)
      specs = valid_specs_for(leaf, model)

      {
        user: seller, store: store, category: leaf,
        title: title, description: demo_description(title, condition),
        price_cents: cents,
        original_price_cents: (@rng.rand < 0.15 ? (cents * (1.1 + @rng.rand * 0.35)).round : nil),
        currency: "EUR", country_code: "ES",
        condition: condition, status: status,
        quantity: store&.business? ? rand(1..6) : 1,
        specs: specs || {}, # column is NOT NULL default {} — never assign nil
        shipping_available: true, local_pickup: @rng.rand < 0.35,
        city: city, region: region, postal_code: format("%05d", postal_code_for(region)),
        shipping_price_cents: shipping, free_shipping: shipping.zero?,
        allow_offers: @rng.rand < 0.6,
        published_at: status == :draft ? nil : posted,
        views_count: rand(0..900),
        featured_until: (@rng.rand < 0.12 ? rand(1..20).days.from_now : nil),
        rejection_reason: status == :rejected ? REJECTION_REASONS.sample(random: @rng) : nil,
        sold_at: status == :sold ? rand(1..60).days.ago : nil
      }
    end

    def weighted_condition
      case @rng.rand(100)
      when 0..24 then :used_good
      when 25..49 then :used_like_new
      when 50..69 then :brand_new
      when 70..84 then :open_box
      else :for_parts
      end
    end

    def price_cents_for(condition, new_range, used_range)
      lo, hi = %w[brand_new open_box].include?(condition.to_s) ? new_range : used_range
      base = rand(lo..hi) * 100
      condition.to_s == "for_parts" ? (base * 0.45).round : base
    end

    # Keep only spec keys the leaf accepts and values valid for each
    # attribute's input type (validate_specs on Listing), so a catalog typo
    # can never make the seed blow up.
    def valid_specs_for(leaf, model)
      return nil unless model && model[5]

      allowed = leaf.all_spec_attributes.index_by(&:key)
      model[5].each_with_object({}) do |(key, value), out|
        attribute = allowed[key.to_s]
        next unless attribute

        case attribute.input_type.to_s
        when "select"
          options = attribute.spec_options.pluck(:value)
          out[key.to_s] = value.to_s if options.include?(value.to_s)
        when "multi_select"
          options = attribute.spec_options.pluck(:value)
          values = Array(value).map(&:to_s).select { |v| options.include?(v) }
          out[key.to_s] = values if values.any?
        when "boolean"
          out[key.to_s] = value if [ true, false ].include?(value)
        when "number"
          out[key.to_s] = value.to_s if value.to_s.match?(/\A-?\d+(?:\.\d+)?\z/)
        else # text
          out[key.to_s] = value.to_s if value.to_s.length <= 200
        end
      end
    end

    def root_slug(category)
      node = category
      node = node.parent while node.parent_id
      node.slug
    end

    def generic_title(leaf)
      "#{%w[Nuevo Seminuevo Usado Reacondicionado].sample(random: @rng)} #{leaf.name} #{rand(100..9999)}"
    end

    def demo_description(title, condition)
      parts = [ "#{title}. #{Faker::Lorem.paragraph(sentence_count: 2)}" ]
      parts << CONDITION_BLURBS.fetch(condition.to_s)
      parts << Faker::Lorem.paragraph(sentence_count: rand(2..3)) if @rng.rand < 0.7
      parts << "Acepto cambios por piezas compatibles; escríbeme y lo hablamos." if @rng.rand < 0.25
      parts.join("\n\n")
    end

    def postal_code_for(region)
      code = PROVINCES.find { |p| p["name"] == region }["code"].to_i
      code * 1000 + rand(1..999)
    end

    def finalize_listing(listing, attrs, admin)
      root = root_slug(listing.category)
      if listing.store && (pool = LABEL_POOL[root])
        chosen = pool.select { @rng.rand < 0.25 }
        chosen << "free-shipping" if listing.free_shipping
        listing.update!(labels: Label.where(slug: chosen.uniq)) if chosen.any?
      end

      if listing.store && %w[gaming-pcs gpus].include?(root) && @rng.rand < 0.7
        listing.update!(seller_tags: SellerTag.limit(rand(1..3)).to_a)
      end

      case attrs[:status].to_s
      when "approved"
        ModerationEvent.create!(listing: listing, admin: admin, action: "approved",
                                note: "Aprobado en la revisión automática del seed de demostración.",
                                created_at: listing.published_at)
      when "rejected"
        ModerationEvent.create!(listing: listing, admin: admin, action: "rejected",
                                note: attrs[:rejection_reason], created_at: listing.updated_at)
      end

      attach_photos(listing)
    end

    # Every listing ends with at least one photo. Each slot is independent:
    # a failing fetch/attach is logged and the other slots still run, and if
    # nothing attached at all the Fetcher's placeholder fallback is forced —
    # a listing is never skipped or left photo-less because of images.
    def attach_photos(listing)
      entry = catalog[listing.category.slug] || {}
      query = entry["query"] || listing.category.slug.tr("-", " ")
      attached = 0
      @rng.rand(1..5).times do |slot|
        begin
          result = @fetcher.fetch(query: query, title: listing.title,
                                  category_label: entry["icon"], slot: slot)
          @counts["photos:#{result.source}"] += 1
          attach_photo(listing, result)
          attached += 1
        rescue StandardError => e
          warn "  photo #{slot} skipped for #{listing.title.truncate(40)}: #{e.class}: #{e.message}"
        end
      end
      return if attached.positive?

      warn "  no photo attached to #{listing.title.truncate(40)} — forcing placeholder"
      result = @fetcher.fetch(query: query, title: listing.title,
                              category_label: entry["icon"], slot: 0)
      @counts["photos:#{result.source}"] += 1
      attach_photo(listing, result)
    rescue StandardError => e
      warn "  placeholder attach failed for #{listing.title.truncate(40)}: #{e.class}: #{e.message}"
    end

    # Blobs attach with identify: false (files are local and trusted): the
    # metadata below carries width/height plus the attribution hash that the
    # gallery credit line renders from (see ListingsHelper#photo_credit_tag).
    def attach_photo(listing, result)
      ext = result.content_type.split("/").last.sub("jpeg", "jpg")
      File.open(result.path, "rb") do |io|
        listing.photos.attach(
          io: io,
          filename: "demo#{listing.id}_#{slot_name}.#{ext}",
          content_type: result.content_type,
          identify: false,
          metadata: photo_metadata(result)
        )
      end
    end

    def slot_name = SecureRandom.hex(4)

    def photo_metadata(result)
      meta = { "identified" => true }
      dims = image_dimensions(result.path)
      meta["width"], meta["height"] = dims if dims
      meta["attribution"] = result.attribution if result.attribution
      meta
    end

    def image_dimensions(path)
      out = `magick identify -format "%w %h" #{Shellwords.escape(path)} 2>/dev/null`
      w, h = out.split.map(&:to_i)
      w.positive? && h.positive? ? [ w, h ] : nil
    rescue StandardError
      nil
    end
    # --- social / commerce graph -------------------------------------------------
    def seed_social_graph(admin, buyers, sellers, stores, listings)
      return puts("Social graph already present (demo favourites exist) — leaving it alone.") if Favorite.where(user: demo_users).exists?

      demo_listings = listings.to_a
      approved = demo_listings.select(&:approved?)
      return if approved.empty?

      seed_favorites(buyers, demo_listings)
      seed_follows(buyers, stores)
      seed_saved_searches(buyers)
      conversations = seed_conversations(buyers, demo_listings)
      seed_offers(buyers, demo_listings)
      orders = seed_orders(buyers, demo_listings)
      seed_reviews(orders)
      seed_order_notifications(orders)
      seed_message_notifications(conversations)
      seed_reports(buyers, approved)
      seed_contact_messages
      seed_newsletter_preferences(buyers + sellers)
      @counts["reports:admin_closed"] += close_one_report(admin, approved)
    end

    def seed_favorites(buyers, demo_listings)
      buyers.each do |buyer|
        pool = demo_listings.reject { |l| l.user_id == buyer.id }
        pool.sample(rand(2..10), random: @rng).each do |listing|
          Favorite.create!(user: buyer, listing: listing, price_cents_at_save: listing.price_cents)
          @counts["favorites"] += 1
        end
      end
    end

    def seed_follows(buyers, stores)
      return if stores.empty?

      buyers.sample(40, random: @rng).each do |buyer|
        stores.sample(rand(1..3), random: @rng).each do |store|
          next if store.user_id == buyer.id

          Follow.create!(follower: buyer, store: store)
          @counts["follows"] += 1
        end
      end
    end

    def seed_saved_searches(buyers)
      names = [ "Gráficas RTX baratas", "PC gaming completo", "Portátil para estudiar", "Mandos retro", "Consola PS5", "Componentes para subir el PC" ]
      buyers.sample(15, random: @rng).each_with_index do |buyer, i|
        SavedSearch.create!(
          user: buyer,
          name: names[i % names.size],
          query: [ "rtx", "gaming", "portatil", "retro", "ps5", "ryzen" ].sample(random: @rng),
          filters: { "min_price" => [ 100, 200, 300 ].sample(random: @rng),
                     "max_price" => [ 400, 800, 1500 ].sample(random: @rng),
                     "condition" => %w[used_like_new used_good brand_new].sample(random: @rng) },
          email_alerts: @rng.rand < 0.5
        )
        @counts["saved_searches"] += 1
      end
    end

    def seed_conversations(buyers, demo_listings)
      conversations = []
      demo_listings.select(&:approved?).sample(25, random: @rng).each do |listing|
        buyer = buyers.reject { |b| b.id == listing.user_id }.sample(random: @rng)
        next if buyer.nil? || Conversation.exists?(listing: listing, buyer: buyer)

        conversation = Conversation.create!(listing: listing, buyer: buyer, seller: listing.user)
        script = CONVERSATION_SCRIPTS[rand(CONVERSATION_SCRIPTS.size)]
        opened = rand(1..30).days.ago
        script.first(rand(2..script.size)).each_with_index do |line, i|
          sender = i.even? ? buyer : listing.user
          Message.create!(conversation: conversation, sender: sender, body: line,
                          created_at: opened + (i * rand(10..300)).minutes)
        end
        conversations << conversation
        @counts["conversations"] += 1
      end
      conversations
    end

    def seed_offers(buyers, demo_listings)
      states = %w[pending accepted declined withdrawn expired]
      demo_listings.select { |l| l.approved? && l.allow_offers? }.sample(20, random: @rng).each_with_index do |listing, i|
        buyer = buyers.reject { |b| b.id == listing.user_id }.sample(random: @rng)
        next if buyer.nil? || Offer.exists?(listing: listing, buyer: buyer)

        amount = (listing.price_cents * (0.7 + @rng.rand * 0.25)).round
        offer = Offer.create!(listing: listing, buyer: buyer, amount_cents: amount,
                              expires_at: rand(1..5).days.from_now,
                              created_at: rand(2..20).days.ago)
        case states[i % states.size]
        when "accepted" then offer.accept!
        when "declined" then offer.decline!
        when "withdrawn" then offer.withdraw!
        when "expired" then offer.expire!
        end
        @counts["offers:#{states[i % states.size]}"] += 1
      end
    end

    # Orders walk the real state machine (pay!/ship!/...) and the timestamps
    # are backdated afterwards so conversations and dashboards look lived-in.
    def seed_orders(buyers, demo_listings)
      orders = []
      sold = demo_listings.select(&:sold?)
      approved_for_cancel = demo_listings.select { |l| l.approved? }

      sold.first(14).each_with_index do |listing, i|
        buyer = buyers.reject { |b| b.id == listing.user_id }.sample(random: @rng)
        next if buyer.nil?

        order = build_order(buyer, listing)
        next if order.nil?

        placed = rand(10..80).days.ago
        case i % 7
        when 0 then order.pay!
        when 1 then order.pay! && order.ship!(carrier: carrier, tracking_number: tracking)
        when 2 then walk_to(order, :delivered)
        when 3 then walk_to(order, :completed)
        when 4 then walk_to(order, :completed)
        when 5 then walk_to(order, :disputed)
        when 6 then walk_to(order, :disputed) && order.refund!
        end
        backdate_order(order, placed)
        orders << order
        @counts["orders:#{order.status}"] += 1
      end

      # A couple of abandoned checkouts: pending_payment, cancelled.
      2.times do
        listing = approved_for_cancel[rand(approved_for_cancel.size)]
        buyer = buyers.reject { |b| b.id == listing.user_id }.sample(random: @rng)
        next if buyer.nil?

        order = build_order(buyer, listing)
        next if order.nil?

        order.pay!
        order.cancel!
        backdate_order(order, rand(4..15).days.ago)
        orders << order
        @counts["orders:cancelled"] += 1
      end
      orders
    end

    def build_order(buyer, listing)
      order = Order.create!(buyer: buyer, seller: listing.user, currency: "EUR",
                            shipping_address: shipping_address)
      OrderItem.create!(order: order, listing: listing, title: listing.title,
                        price_cents: listing.price_cents, quantity: 1)
      order.update_columns(subtotal_cents: listing.price_cents,
                           shipping_cents: listing.shipping_price_cents,
                           total_cents: listing.price_cents + listing.shipping_price_cents,
                           payment_provider: "stripe", payment_reference: "demo_#{SecureRandom.hex(8)}")
      order.reload
    rescue StandardError => e
      warn "  order skipped: #{e.class}: #{e.message}"
      nil
    end

    def walk_to(order, target)
      order.pay!
      order.ship!(carrier: carrier, tracking_number: tracking)
      order.mark_delivered!
      order.complete! if target == :completed
      order.open_dispute! if target == :disputed
      order
    end

    def carrier = Order::CARRIERS[rand(Order::CARRIERS.size)]

    def tracking = "PC#{rand(10**12)}"

    def backdate_order(order, placed)
      paid = placed + rand(1..12).hours
      shipped = paid + rand(4..24).hours
      delivered = shipped + rand(1..4).days
      values = { created_at: placed, updated_at: placed, paid_at: order.paid? || order.shipped? ? paid : nil }
      values[:shipped_at] = shipped if %w[shipped delivered completed disputed refunded].include?(order.status)
      values[:delivered_at] = delivered if %w[delivered completed disputed refunded].include?(order.status)
      values[:completed_at] = delivered + rand(1..3).days if order.completed?
      order.update_columns(**values.compact)
    end

    def shipping_address
      street = Faker::Address.street_name
      city, province = sample_location
      {
        name: "#{Faker::Name.first_name} #{Faker::Name.last_name}",
        line1: "#{street} #{rand(1..150)}",
        city: city, province: province,
        postal_code: format("%05d", postal_code_for(province)),
        country_code: "ES", phone: "+34 6#{rand(10**8)}"
      }
    end

    def seed_reviews(orders)
      completed = orders.select(&:completed?).select { |o| o.seller.store.present? }
      completed.each do |order|
        next if @rng.rand < 0.4
        next if Review.exists?(order_id: order.id)

        Review.create!(order: order, reviewer: order.buyer, store: order.seller.store,
                       seller: order.seller, rating: [ 4, 4, 5, 5, 5, 3 ].sample(random: @rng),
                       body: REVIEW_BLURBS[rand(REVIEW_BLURBS.size)])
        @counts["reviews"] += 1
      end
    end

    # The transition! methods do not fan out notifications (that happens in
    # the checkout/pay controllers), so mirror what a buyer would see.
    def seed_order_notifications(orders)
      kind_by_status = {
        "paid" => "order_paid", "shipped" => "order_shipped", "delivered" => "order_delivered",
        "completed" => "order_completed", "cancelled" => "order_cancelled",
        "disputed" => "order_disputed", "refunded" => "order_refunded"
      }
      orders.each do |order|
        kind = kind_by_status[order.status]
        next if kind.nil? || kind == "order_paid"

        Notification.create!(user: order.buyer, kind: kind, payload: { "order_id" => order.id })
        @counts["notifications"] += 1
      end
    end

    def seed_message_notifications(conversations)
      conversations.first(10).each do |conversation|
        last = conversation.messages.order(created_at: :desc).first
        next if last.nil?

        receiver = conversation.other_party(last.sender)
        Notification.create!(user: receiver, kind: "new_message",
                             payload: { "conversation_id" => conversation.id })
        @counts["notifications"] += 1
      end
    end

    def seed_reports(buyers, approved)
      pool = approved.reject { |l| buyers.map(&:id).include?(l.user_id) }.uniq(&:id).sample(3, random: @rng)
      reasons = Report.reasons.keys
      pool.each_with_index do |listing, i|
        Report.create!(listing: listing, user: buyers[i], reason: reasons[i % reasons.size],
                       details: REPORT_DETAILS[i % REPORT_DETAILS.size],
                       created_at: rand(2..20).days.ago)
        @counts["reports"] += 1
      end
    end

    def close_one_report(admin, approved)
      report = Report.open.joins(:listing).merge(Listing.where(user: demo_users)).first
      return 0 if report.nil?

      report.close!("dismissed", admin: admin)
      puts "Closed one demo report (dismissed) as an admin example."
      1
    end

    def seed_contact_messages
      CONTACT_SUBJECTS.each do |subject|
        ContactMessage.create!(
          name: "#{Faker::Name.first_name} #{Faker::Name.last_name}",
          email: Faker::Internet.email(domain: DEMO_DOMAIN),
          subject: subject,
          body: Faker::Lorem.paragraph(sentence_count: rand(2..4)),
          locale: "es",
          created_at: rand(1..45).days.ago
        )
        @counts["contact_messages"] += 1
      end
    end

    def seed_newsletter_preferences(users)
      users.each do |user|
        prefs = user.notification_preferences.presence || User::DEFAULT_EMAIL_PREFERENCES
        next if prefs["email_newsletter"] == (@rng.rand < 0.6)

        user.update!(notification_preferences: prefs.merge("email_newsletter" => @rng.rand < 0.6))
      end
    end

    def report
      puts "\n=== Demo seed summary ==="
      @counts.sort.each { |key, value| puts format("  %-26s %d", key, value) }
      puts format("  %-26s %s", "photo sources", @fetcher.source_counts.inspect)
      puts "  login: admin@#{DEMO_DOMAIN} (password #{PASSWORD}); also seller1..40@, business1..8@, buyer1..60@#{DEMO_DOMAIN}"
    end
  end
end

# frozen_string_literal: true

# Sample marketplace content for local development.
#
# Creates a handful of stores and a catalogue of approved listings so the
# browse pages, filters and facet counts have something to show. Safe to run
# repeatedly: it is keyed on stable names/slugs and skips work when the
# samples already exist. The loader is a no-op outside development (test uses
# fixtures instead).
#
#   bin/rails db:seed
return unless Rails.env.development?

require "faker"

# --- Sample stores -------------------------------------------------------

# `city`/`province` describe the seller location; they are copied onto the
# sample listings (the listing `region` column holds the PROVINCE name — the
# same value the seller location form writes, validated by EsProvince).
SAMPLE_SELLERS = [
  { name: "Componentes Barcelona", store_type: "business",
    city: "Barcelona", province: "Barcelona", vat_number: "B12345678", verified: true },
  { name: "Rig y Gaming Madrid", store_type: "business",
    city: "Madrid", province: "Madrid", vat_number: "B87654321", verified: true },
  { name: "TechValencia Outlet", store_type: "business",
    city: "Valencia", province: "Valencia", vat_number: nil },
  { name: "Marcosused", store_type: "individual",
    city: "Sevilla", province: "Sevilla" },
  { name: "Bilbao PC Parts", store_type: "individual",
    city: "Bilbao", province: "Vizcaya" }
].freeze

def seed_sample_stores!
  SAMPLE_SELLERS.map do |attrs|
    existing = Store.find_by(name: attrs[:name])
    next existing if existing

    # A store belongs to its own user: the schema allows one store per user.
    email = "#{attrs[:name].parameterize}@pcmarket.test"
    username = attrs[:name].parameterize(separator: "_")
    user = User.find_by(email_address: email) ||
      User.create!(email_address: email, username: username,
                   password: "password", password_confirmation: "password")

    Store.create!(
      user: user,
      name: attrs[:name],
      slug: attrs[:name].parameterize,
      store_type: attrs[:store_type],
      vat_number: attrs[:vat_number],
      verified: !!attrs[:verified],
      sales_count: Faker::Number.between(from: 4, to: 240)
    )
  end
end

# --- Sample listings -----------------------------------------------------

# Titles and descriptions are Spanish on purpose: that is the language
# sellers write in and it matches the rest of the development data. Category
# slugs and spec values follow db/seeds/data/*.yml so the facet filters
# actually match these listings.
SAMPLE_LISTINGS = [
  { category: "nvidia-gpus", title: "Tarjeta gráfica RTX 4070 Ti Super Gaming", price: 74_900,
    condition: "brand_new", specs: { "gpu_chipset" => "nvidia", "gpu_memory" => "16", "rgb_lighting" => "none" },
    free_shipping: true, labels: %w[staff-pick] },
  { category: "nvidia-gpus", title: "RTX 4060 Ti 16GB nueva con factura", price: 41_900,
    condition: "brand_new", specs: { "gpu_chipset" => "nvidia", "gpu_memory" => "16",
                                     "rgb_lighting" => "addressable" },
    labels: %w[free-shipping] },
  { category: "nvidia-gpus", title: "RTX 3080 10GB usada, funciona perfectamente", price: 38_500,
    condition: "used_good", specs: { "gpu_chipset" => "nvidia", "gpu_memory" => "10" } },
  { category: "nvidia-gpus", title: "RTX 3060 12GB seminueña en caja abierta", price: 24_900,
    condition: "open_box", specs: { "gpu_chipset" => "nvidia", "gpu_memory" => "12", "rgb_lighting" => "none" },
    local_pickup: true },
  { category: "nvidia-gpus", title: "GTX 1080 Ti 11GB para montaje económico", price: 18_900,
    condition: "used_good", specs: { "gpu_chipset" => "nvidia", "gpu_memory" => "11" } },
  { category: "nvidia-gpus", title: "GTX 1660 Super como nueva, poco uso", price: 15_900,
    condition: "used_like_new", specs: { "gpu_chipset" => "nvidia", "gpu_memory" => "8" },
    labels: %w[staff-pick] },
  { category: "cpus", title: "Procesador Ryzen 7 5800X3D nuevo sellado", price: 28_900,
    condition: "brand_new", specs: { "cpu_brand" => "amd", "cpu_cores" => "8", "cpu_socket" => "am5" },
    free_shipping: true, labels: %w[free-shipping] },
  { category: "cpus", title: "Ryzen 5 5600G con disipador original", price: 13_500,
    condition: "used_good", specs: { "cpu_brand" => "amd", "cpu_cores" => "6", "cpu_socket" => "am4" },
    local_pickup: true },
  { category: "cpus", title: "Intel Core i7-13700K precintado", price: 34_900,
    condition: "brand_new", specs: { "cpu_brand" => "intel", "cpu_cores" => "16", "cpu_socket" => "lga1700" } },
  { category: "cpus", title: "Intel Core i5-12400F usado con caja", price: 12_900,
    condition: "used_good", specs: { "cpu_brand" => "intel", "cpu_cores" => "6", "cpu_socket" => "lga1700" } },
  { category: "memory", title: "Kit 32GB DDR5 6000MHz CL30 nuevo", price: 11_900,
    condition: "brand_new", specs: { "memory_type" => "ddr5", "memory_capacity" => "32", "memory_modules" => "2" },
    labels: %w[free-shipping] },
  { category: "memory", title: "16GB DDR4 3200MHz módulo doble", price: 4_900,
    condition: "used_good", specs: { "memory_type" => "ddr4", "memory_capacity" => "16", "memory_modules" => "2" } },
  { category: "storage", title: "SSD NVMe 2TB M.2 Gen4 nuevo", price: 13_900,
    condition: "brand_new", specs: { "storage_capacity" => "2tb", "storage_interface" => "nvme_ssd",
                                     "storage_form_factor" => "m2" },
    free_shipping: true },
  { category: "storage", title: "SSD M.2 1TB seminueño con disipador", price: 6_900,
    condition: "open_box", specs: { "storage_capacity" => "1tb", "storage_interface" => "nvme_ssd" } },
  { category: "monitors", title: 'Monitor 27" 1440p 165Hz IPS nuevo', price: 27_900,
    condition: "brand_new", specs: { "screen_size" => 27, "refresh_rate" => "165", "resolution" => "1440p" } },
  { category: "monitors", title: 'Monitor 24" 1080p 144Hz usado, sin arañazos', price: 11_500,
    condition: "used_good", specs: { "screen_size" => 24, "refresh_rate" => "144", "resolution" => "1080p" },
    shipping: false, local_pickup: true },
  { category: "monitors", title: 'Monitor curvo 34" ultrawide como nuevo', price: 39_900,
    condition: "used_like_new", specs: { "screen_size" => 34, "refresh_rate" => "144",
                                         "resolution" => "ultrawide" },
    labels: %w[staff-pick] },
  { category: "cases", title: "Torre ATX blanca con cristal templado", price: 7_900,
    condition: "brand_new", specs: { "case_form_factor" => "mid_tower", "case_color" => "white" },
    shipping_price_cents: 690 },
  { category: "cases", title: "Caja mini-tower compacta usada", price: 3_900,
    condition: "used_good", specs: { "case_form_factor" => "mini_tower", "case_color" => "black" },
    shipping: false, local_pickup: true },
  { category: "power-supplies", title: "Fuente 850W 80 Plus Gold nueva", price: 10_900,
    condition: "brand_new", specs: { "psu_wattage" => "850", "psu_brand" => "corsair" },
    labels: %w[free-shipping] },
  { category: "power-supplies", title: "Fuente 650W revisada y garantizada", price: 5_500,
    condition: "used_good", specs: { "psu_wattage" => "650", "psu_brand" => "be-quiet" },
    labels: %w[rare] },
  { category: "motherboards", title: "Placa base AM5 ATX con WiFi nueva", price: 18_900,
    condition: "brand_new", specs: { "cpu_socket" => "am5", "motherboard_form_factor" => "atx",
                                     "memory_type" => "ddr5", "motherboard_networking" => "ethernet_wifi" } },
  { category: "motherboards", title: "Placa LGA1700 micro-ATX usada con su caja", price: 10_900,
    condition: "used_good", specs: { "cpu_socket" => "lga1700", "motherboard_form_factor" => "micro_atx",
                                     "memory_type" => "ddr4" } },
  { category: "headphones", title: "Auriculares gaming 7.1 nuevos con soporte", price: 6_900,
    condition: "brand_new", specs: {}, labels: %w[free-shipping] },
  { category: "headphones", title: "Headset inalámbrico usado, batería perfecta", price: 4_500,
    condition: "used_good", specs: {} },
  { category: "mice", title: "Ratón gaming ligero 58g nuevo", price: 5_900,
    condition: "brand_new", specs: {}, free_shipping: true },
  { category: "mice", title: "Ratón inalámbrico ergonómico como nuevo", price: 3_900,
    condition: "used_like_new", specs: {} },
  { category: "keyboards", title: "Teclado mecánico 60% hot-swap nuevo", price: 8_900,
    condition: "brand_new", specs: {} },
  { category: "keyboards", title: "Teclado tenkeyless usado, teclas impecables", price: 4_900,
    condition: "used_good", specs: {}, local_pickup: true },
  { category: "cpu-coolers", title: "Disipador de aire torre nuevo con pasta", price: 4_900,
    condition: "brand_new", specs: { "cpu_cooler_type" => "air" } },
  { category: "cpu-coolers", title: "AIO 240mm seminueño con accesorios", price: 6_500,
    condition: "open_box", specs: { "cpu_cooler_type" => "aio" }, labels: %w[rare] },
  { category: "gpus", title: "Tarjeta gráfica RTX 4090 tope de gama", price: 159_900,
    condition: "brand_new", specs: { "gpu_chipset" => "nvidia", "gpu_memory" => "24",
                                     "rgb_lighting" => "addressable" },
    free_shipping: true, featured: true, labels: %w[free-shipping] },
  { category: "gpus", title: "GPU AMD RX 7800 XT 16GB nueva", price: 48_900,
    condition: "brand_new", specs: { "gpu_chipset" => "amd", "gpu_memory" => "16" } },
  { category: "gpus", title: "GeForce GT 1030 2GB para oficina", price: 6_900,
    condition: "used_good", specs: { "gpu_chipset" => "nvidia", "gpu_memory" => "2" } },
  { category: "laptops", title: 'Portátil gamer 16" con RTX 4060, nuevo', price: 109_900,
    condition: "brand_new", specs: { "cpu_brand" => "amd", "gpu_chipset" => "nvidia",
                                     "memory_capacity" => "16", "storage_capacity" => "1tb", "screen_size" => 16 },
    featured: true, labels: %w[free-shipping] },
  { category: "laptops", title: 'Portátil usado 15" para estudio', price: 34_900,
    condition: "used_good", specs: { "memory_capacity" => "8", "storage_capacity" => "512gb", "screen_size" => 15 },
    shipping: false, local_pickup: true },
  { category: "home-consoles", title: "Consola nueva sellada con dos mandos", price: 44_900,
    condition: "brand_new", specs: { "platform" => "ps5", "device_brand" => "sony" },
    labels: %w[free-shipping] },
  { category: "home-consoles", title: "Consola usada con dos años de uso", price: 29_900,
    condition: "used_good", specs: { "platform" => "ps5", "device_brand" => "sony" },
    labels: %w[rare] },
  { category: "controllers", title: "Mando inalámbrico nuevo con carga USB-C", price: 6_400,
    condition: "brand_new", specs: {} },
  { category: "games", title: "Juego físico precintado edición estándar", price: 4_900,
    condition: "brand_new", specs: {} },
  { category: "gpus", title: "GPU para repuestos, ventiladores rotos", price: 9_900,
    condition: "for_parts", specs: { "gpu_chipset" => "nvidia", "gpu_memory" => "8" } },
  # Prebuilt/used gaming PCs behind the PC Finder (Phase 7a). Specs carry the
  # free-text gpu_model/cpu_model keys the Performance::Scorer reads, so these
  # listings get a real performance_score and the /pc-finder results page has
  # something to rank.
  { category: "pro-gamer-pcs", title: "PC Gaming RTX 4080 Super, AIO silencioso", price: 189_900,
    condition: "used_like_new", specs: { "gpu_model" => "NVIDIA GeForce RTX 4080 Super",
                                         "cpu_model" => "AMD Ryzen 7 9800X3D" },
    tags: %w[aio-cooling competitive], free_shipping: true, labels: %w[staff-pick] },
  { category: "mid-range-pcs", title: "PC Gaming Ryzen 5 7600X + RTX 4070 1440p", price: 109_900,
    condition: "used_good", specs: { "gpu_model" => "NVIDIA GeForce RTX 4070",
                                     "cpu_model" => "AMD Ryzen 5 7600X" },
    tags: %w[rgb competitive] },
  { category: "value-pcs", title: "PC Gaming barato RTX 3060 para 1080p", price: 64_900,
    condition: "used_good", specs: { "gpu_model" => "NVIDIA GeForce RTX 3060",
                                     "cpu_model" => "Intel Core i5-12400F" } },
  { category: "value-pcs", title: "PC Gaming Ryzen 7 5800X3D calidad-precio", price: 59_900,
    condition: "used_like_new", specs: { "gpu_model" => "AMD Radeon RX 6700 XT",
                                         "cpu_model" => "AMD Ryzen 7 5800X3D" },
    tags: %w[air-cooling] }
].freeze

def seed_sample_listings!(stores)
  seller_cities = SAMPLE_SELLERS.index_by { |s| s[:name] }
  created = 0

  # A couple of sold items make the "recently sold" rail real, and a few
  # discounted ones do the same for the deals rail.
  sold_slots = [ 2, 11, 21 ].to_set
  discounted_slots = [ 4, 9, 15, 25 ].to_set

  SAMPLE_LISTINGS.each_with_index do |sample, index|
    slug = sample[:title].parameterize
    next if Listing.exists?(slug: slug)

    category = Category.find_by(slug: sample[:category])
    unless category
      Rails.logger.warn "  Sample category #{sample[:category]} missing, skipping listing"
      next
    end

    store = stores[index % stores.size]
    seller_info = seller_cities.fetch(store.name)

    # Keep only the spec attributes that this category (or an ancestor)
    # declares, so the filter sidebar offers values with hits.
    attribute_keys = category.all_spec_attributes.map(&:key).to_set
    specs = sample[:specs].slice(*attribute_keys)

    price = sample[:price]
    original = if discounted_slots.include?(index)
                 ((price / 0.85).round / 100) * 100
    end

    listing = Listing.new(
      user: store.user,
      store: store,
      category: category,
      title: sample[:title],
      slug: slug,
      description: "#{sample[:title]}. #{Faker::Lorem.paragraph(sentence_count: 4)} " \
                   "Se vende por cambio de equipo. Se puede ver sin compromiso.",
      price_cents: price,
      original_price_cents: original,
      currency: "EUR",
      country_code: "ES",
      condition: sample[:condition],
      status: sold_slots.include?(index) ? "sold" : "approved",
      specs: specs,
      city: seller_info[:city],
      region: seller_info[:province],
      shipping_available: sample.fetch(:shipping, true),
      local_pickup: sample.fetch(:local_pickup, false),
      free_shipping: sample.fetch(:free_shipping, false),
      shipping_price_cents: sample.fetch(:shipping_price_cents, 0),
      allow_offers: sample[:condition] != "brand_new",
      views_count: Faker::Number.between(from: 3, to: 940),
      favorites_count: Faker::Number.between(from: 0, to: 60),
      published_at: Faker::Time.between(from: 60.days.ago, to: 1.minute.ago)
    )
    listing.sold_at = 3.days.ago if sold_slots.include?(index)
    listing.featured_until = 7.days.from_now if sample[:featured]
    listing.labels = Label.where(slug: sample[:labels]) if sample[:labels]
    if sample[:tags]
      listing.seller_tags = SellerTag.where(slug: sample[:tags])
    elsif index.even?
      listing.seller_tags = SellerTag.order(:id).to_a.rotate(index).first(2)
    end
    listing.save!
    created += 1
  end

  puts "  Created #{created} sample listings"
  created
end

# --- Sample reviews ------------------------------------------------------

SAMPLE_REVIEW_BODIES = [
  "Todo perfecto, envío rapidísimo y bien embalado.",
  "Producto tal y como se describía, repetiré.",
  "Buena comunicación y precio ajustado.",
  "Tardó un poco más de lo esperado pero todo bien."
].freeze

# Reviews hang off delivered orders, so each sample review gets a minimal
# completed order of its own (the review model requires one order per review).
def seed_sample_reviews!(stores)
  buyer = User.find_by(email_address: "sample-buyer@pcmarket.test") ||
    User.create!(email_address: "sample-buyer@pcmarket.test", username: "sample_buyer",
                 password: "password", password_confirmation: "password")

  created = 0
  stores.first(3).each_with_index do |store, store_index|
    4.times do |i|
      reference = "sample-review-#{store_index}-#{i}"
      next if Order.exists?(payment_reference: reference)

      amount = Faker::Number.between(from: 2_000, to: 60_000)
      order = Order.create!(
        buyer: buyer,
        seller: store.user,
        status: "delivered",
        subtotal_cents: amount,
        total_cents: amount,
        payment_reference: reference,
        delivered_at: Faker::Time.between(from: 40.days.ago, to: 2.days.ago)
      )

      Review.create!(
        order: order,
        reviewer: buyer,
        store: store,
        seller: store.user,
        rating: [ 5, 4, 5, 3 ][i],
        body: SAMPLE_REVIEW_BODIES[i],
        created_at: Faker::Time.between(from: 40.days.ago, to: 1.hour.ago)
      )
      created += 1
    end
  end

  puts "  Created #{created} sample reviews"
  created
end

# --- Sample photos -------------------------------------------------------

SAMPLE_PHOTO_DIR = Rails.root.join("tmp", "sample_photos")
SAMPLE_PHOTO_PALETTE = [
  %w[#1e3a8a #38bdf8], %w[#14532d #4ade80], %w[#4c1d95 #c084fc],
  %w[#7c2d12 #fb923c], %w[#0c4a6e #67e8f9], %w[#3f3f46 #a1a1aa]
].freeze

# Placeholder product shots, rendered by ImageMagick and cached on disk, so
# the browse and show pages exercise the real variant/lazy-image pipeline.
def sample_photo_path(index, slot)
  FileUtils.mkdir_p(SAMPLE_PHOTO_DIR)
  path = SAMPLE_PHOTO_DIR.join("listing-#{index}-#{slot}.png")
  return path if File.exist?(path)

  from, to = SAMPLE_PHOTO_PALETTE[(index + slot) % SAMPLE_PHOTO_PALETTE.size]
  rendered = system("magick", "-size", "1200x900", "gradient:#{from}-#{to}",
                    "(", "-size", "1200x900", "xc:none",
                         "-fill", "rgba(255,255,255,0.22)",
                         "-draw", "roundrectangle 220,320 980,580 28,28", ")",
                    "-composite", path.to_s)
  path if rendered
end

def seed_sample_photos!(stores)
  candidates = Listing.joins(:store).where(store: Store.where(name: stores.map { |s| s[:name] })).order(:id)

  attached = 0
  candidates.each_with_index do |listing, index|
    next if listing.photos.attached?

    shots = (index % 5).zero? ? 3 : (index % 3).zero? ? 1 : 2
    shots.times do |slot|
      path = sample_photo_path(index, slot)
      next if path.nil?

      File.open(path) do |file|
        listing.photos.attach(io: file, filename: path.basename.to_s, content_type: "image/png")
      end
      attached += 1
    end
  end

  missing = candidates.count { |listing| listing.photos.blank? }
  Rails.logger.warn "  Could not render sample photos (is ImageMagick installed?)" if missing.positive? && attached.zero?

  puts "  Attached #{attached} sample photos"
  attached
end

puts "Seeding sample marketplace content (#{Rails.env})"
sample_stores = seed_sample_stores!
seed_sample_listings!(sample_stores)
seed_sample_photos!(sample_stores)
seed_sample_reviews!(sample_stores)
puts "Sample content ready: #{Listing.joins(:store).where(store: Store.where(name: SAMPLE_SELLERS.map { |s| s[:name] })).count} sample listings"

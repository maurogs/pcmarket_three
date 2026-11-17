# frozen_string_literal: true

require "fileutils"
require "zlib"

module DemoImages
  # Offline fallback photo: a 1200x900 PNG rendered with ImageMagick —
  # brand gradient, the category's icon label as watermark text and the
  # product title. Used when no network and no cached photo is available,
  # so seeding always succeeds. When ImageMagick is missing or fails, a
  # pure-Ruby gradient PNG is written instead: render returns a readable
  # image path or nil only if the disk itself refuses the write.
  module Placeholder
    WIDTH = 1200
    HEIGHT = 900
    FALLBACK_WIDTH = 120
    FALLBACK_HEIGHT = 90

    # Brand-adjacent gradients (primary indigo -> accent orange first).
    PALETTE = [
      %w[#4f46e5 #f97316], %w[#1e3a8a #38bdf8], %w[#14532d #4ade80],
      %w[#4c1d95 #c084fc], %w[#7c2d12 #fb923c], %w[#0c4a6e #67e8f9],
      %w[#3f3f46 #a1a1aa], %w[#831843 #f472b6]
    ].freeze

    FONT_CANDIDATES = [
      "/System/Library/Fonts/Supplemental/Arial.ttf",
      "/System/Library/Fonts/Helvetica.ttc",
      "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
      "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
      "/usr/share/fonts/truetype/ubuntu/Ubuntu-R.ttf"
    ].freeze

    class << self
      # Renders `<path>` (creating parent directories) and returns it. Falls
      # back to a pure-Ruby PNG when ImageMagick is missing or errors out;
      # returns nil only if even that write fails.
      def render(title:, category_label: nil, path:, seed: 0)
        FileUtils.mkdir_p(File.dirname(path))
        return path if render_gradient(path, title:, category_label:, seed:)

        write_fallback_png(path) ? path : nil
      end

      # ImageMagick gradient + text tile; false on any failure.
      def render_gradient(path, title:, category_label: nil, seed: 0)
        return false unless system("magick", "-version", out: File::NULL, err: File::NULL)

        from, to = PALETTE[seed % PALETTE.size]
        args = base_args(from, to)
        if (font = font_path)
          args += text_args(font, category_label, title)
        end

        # IM7 CLI: all operations first, output file last.
        system("magick", *args, path, out: File::NULL, err: File::NULL) && File.exist?(path)
      end

      def font_path
        @font_path ||= ([ ENV["DEMO_IMAGE_FONT"] ] + FONT_CANDIDATES).compact.find do |path|
          File.exist?(path) && text_probe_ok?(path)
        end
      end

      private

      # Minimal valid PNG (diagonal brand gradient, no text) built with only
      # Zlib — used when ImageMagick is unavailable.
      def write_fallback_png(path)
        raw = +""
        FALLBACK_HEIGHT.times do |y|
          raw << 0.chr # filter byte: none
          t = y / (FALLBACK_HEIGHT - 1)
          from, to = PALETTE.first
          r, g, b = rgb(from).zip(rgb(to)).map { |a, z| (a + (z - a) * t).round }
          pixel = [ r, g, b ].pack("C3")
          raw << pixel * FALLBACK_WIDTH
        end

        png = "\x89PNG\r\n\x1A\n".b
        png << png_chunk("IHDR", [ FALLBACK_WIDTH, FALLBACK_HEIGHT ].pack("N2") + [ 8, 2, 0, 0, 0 ].pack("C5"))
        png << png_chunk("IDAT", Zlib::Deflate.deflate(raw))
        png << png_chunk("IEND", "")
        File.binwrite(path, png)
        File.exist?(path)
      rescue StandardError
        false
      end

      def png_chunk(type, data)
        [ data.bytesize ].pack("N") + type + data + [ Zlib.crc32(type + data) ].pack("N")
      end

      def rgb(hex)
        [ hex[1, 2], hex[3, 2], hex[5, 2] ].map { |pair| pair.to_i(16) }
      end

      def base_args(from, to)
        [
          "-size", "#{WIDTH}x#{HEIGHT}", "gradient:#{from}-#{to}",
          "(", "-size", "#{WIDTH}x#{HEIGHT}", "xc:none",
               "-fill", "rgba(255,255,255,0.14)",
               "-draw", "roundrectangle 180,300 1020,600 32,32", ")",
          "-composite"
        ]
      end

      def text_args(font, category_label, title)
        [
          "-font", font,
          "-fill", "rgba(255,255,255,0.75)", "-gravity", "North", "-pointsize", "46",
          "-annotate", "+0+190", safe(category_label || "PCMarket"),
          "-fill", "rgba(255,255,255,0.95)", "-gravity", "South", "-pointsize", "38",
          "-annotate", "+0+320", safe(truncate(title))
        ]
      end

      # Control characters and stray newlines break -annotate.
      def safe(text)
        text.to_s.gsub(/[[:cntrl:]]/, " ").squeeze(" ").strip
      end

      def truncate(text)
        text = safe(text)
        text.length > 46 ? "#{text[0, 43]}..." : text
      end

      # One small render to prove freetype actually works with this font
      # (ImageMagick builds without a font config fail even with a valid path).
      def text_probe_ok?(font)
        system("magick", "-size", "10x10", "xc:white", "-font", font,
               "-annotate", "0", "a", "null:",
               out: File::NULL, err: File::NULL)
      rescue StandardError
        false
      end
    end
  end
end

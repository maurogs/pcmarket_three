# Turns a listing's `specs` gpu_model/cpu_model strings into a relative
# 0-1000 `performance_score` using the tier tables in
# config/data/gpu_tiers.yml and config/data/cpu_tiers.yml.
#
# Model names are fuzzy-normalized before the lookup: downcase, brand words
# (nvidia/geforce/radeon/intel/amd/core/graphics) dropped — "radeon" only in
# front of "rx …" so Radeon iGPUs like "780M" keep their token — laptop/mobile
# GPU suffixes dropped (mobile parts score as their desktop sibling, a
# documented approximation), then every non-alphanumeric character is
# stripped, so "NVIDIA GeForce RTX 4070 Super" and "RTX-4070 SUPER" both
# become "rtx4070super". Tier YAML keys are stored in that compact form.
#
# Weighting: 75% GPU + 25% CPU. When only one of the two is known its score
# is used as-is (weights re-normalized); the result is nil only when NEITHER
# name resolves to a tier — unknown models stay unscored instead of guessing.
# Scores are only computed for gaming PCs, workstations and laptops
# (Listing::SCORABLE_CATEGORY_SLUGS).
module Performance
  class Scorer
    GPU_TIERS = YAML.load_file(Rails.root.join("config/data/gpu_tiers.yml")).freeze
    CPU_TIERS = YAML.load_file(Rails.root.join("config/data/cpu_tiers.yml")).freeze

    # Brand / noise words removed before matching. "radeon" is handled
    # separately (only stripped when followed by "rx").
    DROP_WORDS = %w[nvidia geforce intel amd core graphics].freeze
    MOBILE_SUFFIXES = %w[laptop mobile notebook].freeze

    class << self
      # The specs-hash entry point used by Listing's before_save.
      def score_from_specs(specs)
        specs = specs.to_h
        score_for(gpu_model: specs["gpu_model"].presence || specs[:gpu_model],
                  cpu_model: specs["cpu_model"].presence || specs[:cpu_model])
      end

      def score_for(gpu_model:, cpu_model:)
        gpu = gpu_score(gpu_model)
        cpu = cpu_score(cpu_model)
        return nil if gpu.nil? && cpu.nil?
        return gpu if cpu.nil?
        return cpu if gpu.nil?

        ((gpu * 0.75) + (cpu * 0.25)).round
      end

      def gpu_score(name)
        return nil if name.blank?

        GPU_TIERS[normalize(name, :gpu)]
      end

      def cpu_score(name)
        return nil if name.blank?

        CPU_TIERS[normalize(name, :cpu)]
      end

      def normalize(name, component)
        text = " #{name.to_s.downcase} "
        text = text.gsub(/radeon(?=\s*rx)/, " ") if component == :gpu
        drop = component == :gpu ? DROP_WORDS + MOBILE_SUFFIXES + %w[gpu] : DROP_WORDS
        text.split(/[^a-z0-9]+/).reject { |w| drop.include?(w) }.join
      end
    end
  end
end

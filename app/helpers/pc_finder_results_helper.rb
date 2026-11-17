module PcFinderResultsHelper
  # Applied quiz answers as chips: [label, href]; href nil → static chip
  # (resolution/FPS are edited by re-running with a different value).
  def finder_result_chips(results)
    filters = results.filters
    tag_names = SellerTag.where(slug: filters[:tags]).index_by(&:slug)

    chips = filters[:games].map do |slug|
      name = Performance::FpsEstimator::GAMES.dig(slug, "name")
      [ name, finder_filtered_path(results, except_games: [ slug ]) ]
    end

    chips << [ filters[:resolution], nil ]
    chips << [ "#{filters[:fps]} FPS", nil ]

    if filters[:budget]
      chips << [ t("pc_finders.show.budgets.#{filters[:budget]}"),
                 finder_filtered_path(results, drop: [ :budget ]) ]
    end

    filters[:tags].each do |slug|
      chips << [ tag_names[slug]&.name || slug, finder_filtered_path(results, drop: [ :tags ], remove_tag: slug) ]
    end

    chips
  end

  private

  def finder_filtered_path(results, except_games: [], drop: [], remove_tag: nil)
    filters = results.filters
    games = filters[:games] - except_games
    tags = filters[:tags] - [ remove_tag ].compact

    params = {
      games: games.presence,
      resolution: filters[:resolution],
      fps: filters[:fps],
      budget: (filters[:budget] unless drop.include?(:budget)),
      tags: tags.presence
    }.compact
    params = { resolution: params[:resolution], fps: params[:fps] } if params[:games].nil?

    pc_finder_results_path(params)
  end
end

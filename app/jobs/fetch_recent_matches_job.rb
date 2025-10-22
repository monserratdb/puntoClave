class FetchRecentMatchesJob < ApplicationJob
  queue_as :default

  def perform(limit = 100)
    begin
      svc = TennisApiService.new
      svc.fetch_recent_matches(limit)
      Rails.logger.info "FetchRecentMatchesJob: completed fetch_recent_matches(#{limit})"
    rescue => e
      Rails.logger.error "FetchRecentMatchesJob failed: #{e.message}"
    end
  end
end

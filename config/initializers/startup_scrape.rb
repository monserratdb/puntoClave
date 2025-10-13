# Run a lightweight scrape on server startup in development to ensure upcoming matches are present.
# This is intentionally conservative: only runs in development and can be disabled with
# DISABLE_STARTUP_SCRAPE=true or FORCE_SAMPLE=true.
begin
  should_run = (Rails.env.development? || ENV['STARTUP_SCRAPE'] == 'true') && ENV['DISABLE_STARTUP_SCRAPE'] != 'true' && ENV['FORCE_SAMPLE'] != 'true'

  if should_run
    Thread.new do
      sleep 5 # let the app boot a bit
      begin
        Rails.logger.info "Startup scrape: attempting to populate upcoming fixtures (prefer espn calendar)"
        svc = TennisApiService.new

        # Prefer the calendar/html extraction (often contains upcoming fixtures)
        matches = []
        begin
          matches = svc.espn_calendar(200)
        rescue => e
          Rails.logger.debug "espn_calendar call failed: #{e.message}"
          matches = []
        end

        # If we found matches, persist them; otherwise fall back to the broader fetch
        if matches.any?
          Rails.logger.info "Startup scrape: espn_calendar returned #{matches.length} matches, persisting"
          begin
            svc.persist_matches(matches)
            Rails.logger.info "Startup scrape: persisted #{matches.length} calendar matches"
          rescue => e
            Rails.logger.error "Startup scrape persist failed: #{e.message}"
          end
        else
          Rails.logger.info "Startup scrape: espn_calendar returned 0 matches, falling back to fetch_recent_matches"
          begin
            svc.fetch_recent_matches(200)
            Rails.logger.info "Startup scrape: finished fetch_recent_matches fallback"
          rescue => e
            Rails.logger.error "Startup scrape fallback failed: #{e.message}"
          end
        end
      rescue => e
        Rails.logger.error "Startup scrape failed: #{e.message}"
      end
    end
  else
    Rails.logger.info "Startup scrape skipped (env=#{Rails.env}, DISABLE_STARTUP_SCRAPE=#{ENV['DISABLE_STARTUP_SCRAPE']}, FORCE_SAMPLE=#{ENV['FORCE_SAMPLE']}, STARTUP_SCRAPE=#{ENV['STARTUP_SCRAPE']})"
  end
rescue => e
  Rails.logger.error "startup_scrape initializer error: #{e.message}"
end

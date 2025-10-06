namespace :scrape do
  desc "Run a scraping daemon that updates ESPN players and recent matches every N minutes while active. Configure SCRAPE_INTERVAL_MINUTES and FORCE_REPLACE=true"
  task daemon: :environment do
    interval_minutes = (ENV['SCRAPE_INTERVAL_MINUTES'] || 30).to_i
    interval_seconds = [interval_minutes, 1].max * 60

    puts "Starting scraping daemon (interval: "+interval_minutes.to_s+" minutes). Press Ctrl-C to stop."

    begin
      loop do
        start_time = Time.current
        puts "[#{start_time}] Scrape iteration starting..."

        api = TennisApiService.new

        # Optionally replace players table if requested (dangerous, so requires env)
        if ENV['FORCE_REPLACE'] == 'true'
          puts "FORCE_REPLACE=true: replacing players table from ESPN rankings (destructive)"
          begin
            rankings = api.espn_rankings
            ActiveRecord::Base.transaction do
              Player.delete_all
              rankings.each do |pdata|
                Player.create!(name: pdata[:name], country: pdata[:country], rank: pdata[:rank], points: pdata[:points])
              end
            end
            puts "Players replaced with #{Player.count} entries (source: espn)"
          rescue => e
            puts "Error replacing players: #{e.message}"
            Rails.logger.error e.full_message
          end
        else
          # Non-destructive sync (update/create)
          begin
            puts "Syncing players from ESPN rankings..."
            api.fetch_atp_rankings
            puts "Players sync complete (#{Player.count} players). Source: #{api.last_source}" 
          rescue => e
            puts "Error syncing players: #{e.message}"
            Rails.logger.error e.full_message
          end
        end

        # Fetch recent/upcoming matches (this will attempt 365Scores among other heuristics)
        begin
          puts "Fetching recent/upcoming matches (prefer 365Scores)..."
          matches = api.fetch_recent_matches(100)
          puts "Fetched/updated #{matches.length} matches (source: #{api.last_source})"
        rescue => e
          puts "Error fetching matches: #{e.message}"
          Rails.logger.error e.full_message
        end

        elapsed = Time.current - start_time
        sleep_time = interval_seconds - elapsed
        if sleep_time > 0
          puts "Iteration finished. Sleeping #{sleep_time.round}s until next run..."
          sleep(sleep_time)
        else
          puts "Iteration took longer (#{elapsed.round}s) than interval; starting next immediately."
        end
      end
    rescue Interrupt
      puts "Scraping daemon stopped by user (Ctrl-C)"
    rescue => e
      puts "Scraping daemon aborted with error: #{e.message}"
      Rails.logger.error e.full_message
    end
  end
end

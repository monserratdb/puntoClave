namespace :db do
  namespace :scrape do
    desc 'Run initial scraping to populate players and matches using TennisApiService (ESPN-focused)'
    task initial: :environment do
      puts "Starting initial scraping (ESPN)..."

      begin
        api = TennisApiService.new
        api_players = api.fetch_atp_rankings
        puts "TennisApiService used source: #{api.last_source || 'unknown'}; players: #{api_players.length}"

        api_matches = api.fetch_recent_matches(100)
        puts "TennisApiService used source for matches: #{api.last_source || 'unknown'}; matches: #{api_matches.length}"

        puts "Initial scraping complete."
      rescue => e
        puts "Error during scraping: #{e.message}"
        Rails.logger.error "db:scrape:initial failed: #{e.full_message}"
      end
    end
  end
end

namespace :db do
  namespace :scrape do
    desc 'Sync players from ESPN rankings (update or create)'
    task espn_sync_players: :environment do
      puts "Syncing players from ESPN rankings..."
      begin
  api = TennisApiService.new
  rankings = api.espn_rankings
  puts "ESPN returned #{rankings.length} players"
  api.update_players(rankings)
        puts "Sync complete."
      rescue => e
        puts "Error syncing ESPN players: #{e.message}"
        Rails.logger.error e.full_message
      end
    end

    desc 'Replace players with ESPN rankings (destructive). Set FORCE_REPLACE=true to allow.'
    task espn_replace_players: :environment do
      if ENV['FORCE_REPLACE'] == 'true'
        puts "Replacing players table using ESPN rankings (destructive)"
        begin
          api = TennisApiService.new
          rankings = api.espn_rankings
          puts "ESPN returned #{rankings.length} players"
          ActiveRecord::Base.transaction do
            puts "Deleting existing players..."
            Player.delete_all
            rankings.each do |pdata|
              Player.create!(name: pdata[:name], country: pdata[:country], rank: pdata[:rank], points: pdata[:points])
            end
          end
          puts "Replace complete. Inserted #{Player.count} players."
        rescue => e
          puts "Error during replace: #{e.message}"
          Rails.logger.error e.full_message
          raise ActiveRecord::Rollback
        end
      else
        puts "Destructive replace disabled. Set FORCE_REPLACE=true to allow replacing the players table."
      end
    end
  end
end

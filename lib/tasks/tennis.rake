namespace :tennis do
  desc "Scrape ATP player rankings and create sample matches"
  task scrape_data: :environment do
    puts "Starting ATP data scraping..."
    
    scraper = AtpScraperService.new
    
    # Scrape player rankings
    puts "Scraping player rankings..."
    players = scraper.scrape_rankings
    puts "✅ Scraped #{players.length} players"
    
    # Create sample matches
    puts "Creating sample matches..."
    matches = scraper.scrape_recent_matches(30)
    puts "✅ Created #{matches.length} sample matches"
    
    puts "✅ Data scraping completed successfully!"
    puts "Total players: #{Player.count}"
    puts "Total matches: #{Match.count}"
  end
  
  desc "Generate sample predictions for testing"
  task generate_predictions: :environment do
    puts "Generating sample predictions..."
    
    players = Player.limit(10)
    predictor = TennisPredictor.new
    prediction_count = 0
    
    5.times do
      player1 = players.sample
      player2 = players.where.not(id: player1.id).sample
      next unless player2
      
      result = predictor.predict_match_winner(player1, player2)
      prediction_count += 1 if result[:prediction]
    end
    
    puts "✅ Generated #{prediction_count} sample predictions"
    puts "Total predictions: #{Prediction.count}"
  end
end
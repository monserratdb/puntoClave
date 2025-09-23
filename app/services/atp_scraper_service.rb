class AtpScraperService
  include HTTParty
  
  BASE_URL = 'https://www.atptour.com'
  
  def initialize
    @headers = {
      'User-Agent' => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
      'Accept-Language' => 'en-US,en;q=0.5',
      'Accept-Encoding' => 'gzip, deflate, br',
      'DNT' => '1',
      'Connection' => 'keep-alive',
      'Upgrade-Insecure-Requests' => '1'
    }
    self.class.default_timeout 30
  end
  
  def scrape_rankings
    begin
      url = "#{BASE_URL}/en/rankings/singles"
      puts "Trying to scrape: #{url}"
      
      response = HTTParty.get(url, headers: @headers, timeout: 30)
      puts "Response code: #{response.code}"
      
      if response.success?
        doc = Nokogiri::HTML(response.body)
        players_data = []
        
        # Try multiple selectors as websites change their structure
        ranking_rows = doc.css('tbody tr, .player-row, .rankings-table tr')
        puts "Found #{ranking_rows.length} potential player rows"
        
        if ranking_rows.empty?
          puts "No ranking data found, creating sample data instead"
          return create_sample_players
        end
        
        # Parse the rankings table
        ranking_rows.each_with_index do |row, index|
          break if index >= 50 # Limit to top 50 players
          
          cells = row.css('td')
          next if cells.empty?
          
          # Try to extract data with flexible selectors
          rank_text = cells[0]&.text&.strip || ""
          name_text = cells[1]&.text&.strip || ""
          country_text = cells[1]&.css('img')&.first&.[]('alt') || ""
          points_text = cells[2]&.text&.strip || ""
          
          rank = rank_text.gsub(/\D/, '').to_i
          points = points_text.gsub(/[^\d]/, '').to_i
          
          next if name_text.empty? || rank == 0
          
          players_data << {
            name: name_text,
            country: country_text.empty? ? "Unknown" : country_text,
            rank: rank,
            points: points > 0 ? points : rand(1000..5000)
          }
        end
        
        if players_data.empty?
          puts "No valid player data extracted, creating sample data"
          return create_sample_players
        end
        
        # Create or update players
        players_data.each do |player_data|
          player = Player.find_or_create_by(name: player_data[:name]) do |p|
            p.country = player_data[:country]
            p.rank = player_data[:rank]
            p.points = player_data[:points]
          end
          
          # Update existing players
          if player.persisted?
            player.update(
              country: player_data[:country],
              rank: player_data[:rank],
              points: player_data[:points]
            )
          end
        end
        
        Rails.logger.info "Successfully scraped #{players_data.length} players"
        players_data
      else
        Rails.logger.error "Failed to fetch rankings: #{response.code} - #{response.message}"
        puts "HTTP error, creating sample data instead"
        create_sample_players
      end
    rescue => e
      Rails.logger.error "Error scraping rankings: #{e.message}"
      puts "Exception occurred: #{e.message}"
      puts "Creating sample data instead"
      create_sample_players
    end
  end
  
  def create_sample_players
    # Create realistic sample data when scraping fails
    sample_players = [
      { name: "Novak Djokovic", country: "Serbia", rank: 1, points: 9855 },
      { name: "Carlos Alcaraz", country: "Spain", rank: 2, points: 8805 },
      { name: "Daniil Medvedev", country: "Russia", rank: 3, points: 6630 },
      { name: "Alexander Zverev", country: "Germany", rank: 4, points: 5715 },
      { name: "Andrey Rublev", country: "Russia", rank: 5, points: 4805 },
      { name: "Stefanos Tsitsipas", country: "Greece", rank: 6, points: 4445 },
      { name: "Rafael Nadal", country: "Spain", rank: 7, points: 4245 },
      { name: "Holger Rune", country: "Denmark", rank: 8, points: 3940 },
      { name: "Casper Ruud", country: "Norway", rank: 9, points: 3855 },
      { name: "Taylor Fritz", country: "USA", rank: 10, points: 3310 },
      { name: "Jannik Sinner", country: "Italy", rank: 11, points: 3165 },
      { name: "Felix Auger-Aliassime", country: "Canada", rank: 12, points: 2905 },
      { name: "Alex de Minaur", country: "Australia", rank: 13, points: 2745 },
      { name: "Tommy Paul", country: "USA", rank: 14, points: 2595 },
      { name: "Lorenzo Musetti", country: "Italy", rank: 15, points: 2390 }
    ]
    
    sample_players.each do |player_data|
      Player.find_or_create_by(name: player_data[:name]) do |p|
        p.country = player_data[:country]
        p.rank = player_data[:rank]
        p.points = player_data[:points]
      end
    end
    
    Rails.logger.info "Created #{sample_players.length} sample players"
    sample_players
  end
  
  def scrape_recent_matches(limit = 20)
    begin
      # For demo purposes, we'll create some sample matches
      # In a real implementation, you'd scrape actual match results
      players = Player.limit(10)
      return [] if players.count < 2
      
      matches_data = []
      tournaments = ['Australian Open', 'French Open', 'Wimbledon', 'US Open', 'ATP Masters', 'ATP 500']
      surfaces = ['Hard', 'Clay', 'Grass']
      
      limit.times do
        player1 = players.sample
        player2 = players.where.not(id: player1.id).sample
        next unless player2
        
        # Simulate match result based on ranking (higher ranked player more likely to win)
        winner = player1.rank < player2.rank ? player1 : player2
        winner = [player1, player2].sample if rand < 0.3 # Add some randomness
        
        match_data = {
          player1: player1,
          player2: player2,
          winner: winner,
          tournament: tournaments.sample,
          date: rand(30.days).seconds.ago.to_date,
          score: generate_random_score,
          surface: surfaces.sample
        }
        
        match = Match.create!(match_data)
        matches_data << match_data
      end
      
      Rails.logger.info "Created #{matches_data.length} sample matches"
      matches_data
    rescue => e
      Rails.logger.error "Error creating sample matches: #{e.message}"
      []
    end
  end
  
  private
  
  def generate_random_score
    # Generate realistic tennis scores
    scores = [
      "6-4, 6-2",
      "7-6, 6-3",
      "6-3, 4-6, 6-2",
      "7-5, 6-4",
      "6-2, 6-3",
      "6-4, 3-6, 6-4",
      "7-6, 7-6",
      "6-1, 6-2"
    ]
    scores.sample
  end
end
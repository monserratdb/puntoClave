# Create sample matches
players = Player.all
tournaments = ['Australian Open', 'French Open', 'Wimbledon', 'US Open', 'ATP Masters', 'ATP 500']
surfaces = ['Hard', 'Clay', 'Grass']
scores = ['6-4, 6-2', '7-6, 6-3', '6-3, 4-6, 6-2', '7-5, 6-4', '6-2, 6-3']

15.times do |i|
  player1 = players.sample
  player2 = players.where.not(id: player1.id).sample
  
  # Higher ranked player more likely to win (but add some randomness)
  winner = player1.rank < player2.rank ? player1 : player2
  winner = [player1, player2].sample if rand < 0.3
  
  match = Match.create!(
    player1: player1,
    player2: player2,
    winner: winner,
    tournament: tournaments.sample,
    date: rand(60.days).seconds.ago.to_date,
    score: scores.sample,
    surface: surfaces.sample
  )
  
  puts "Created match: #{player1.name} vs #{player2.name}, winner: #{winner.name}"
end

puts "Created #{Match.count} matches successfully!"
# Tennis prediction ML algorithm service
class MatchPredictor
  def initialize
    # Simple ML model based on ELO-like rating system and statistical analysis
  end
  
  def predict_match_winner(player1, player2)
    begin
      # Calculate prediction based on multiple factors
      ranking_score = calculate_ranking_score(player1, player2)
      head_to_head_score = calculate_head_to_head_score(player1, player2)
      recent_form_score = calculate_recent_form_score(player1, player2)
      points_score = calculate_points_score(player1, player2)
      
      # Weighted combination of factors
      player1_score = (
        ranking_score[:player1] * 0.3 +
        head_to_head_score[:player1] * 0.2 +
        recent_form_score[:player1] * 0.3 +
        points_score[:player1] * 0.2
      )
      
      player2_score = (
        ranking_score[:player2] * 0.3 +
        head_to_head_score[:player2] * 0.2 +
        recent_form_score[:player2] * 0.3 +
        points_score[:player2] * 0.2
      )
      
      # Normalize to get probability
      total_score = player1_score + player2_score
      player1_probability = player1_score / total_score
      player2_probability = player2_score / total_score
      
      predicted_winner = player1_probability > player2_probability ? player1 : player2
      confidence = [player1_probability, player2_probability].max
      
      # Create prediction record
      prediction = Prediction.create!(
        player1: player1,
        player2: player2,
        predicted_winner: predicted_winner,
        confidence: confidence,
        prediction_date: Time.current
      )
      
      {
        predicted_winner: predicted_winner,
        confidence: confidence,
        player1_probability: player1_probability,
        player2_probability: player2_probability,
        prediction: prediction
      }
    rescue => e
      Rails.logger.error "Error predicting match: #{e.message}"
      {
        predicted_winner: player1,
        confidence: 0.5,
        player1_probability: 0.5,
        player2_probability: 0.5,
        prediction: nil
      }
    end
  end
  
  private
  
  def calculate_ranking_score(player1, player2)
    # Better ranking = higher score
    rank1 = player1.rank || 1000
    rank2 = player2.rank || 1000
    
    # Inverse ranking (lower rank number = better)
    score1 = 1.0 / (rank1 + 1)
    score2 = 1.0 / (rank2 + 1)
    
    total = score1 + score2
    
    {
      player1: score1 / total,
      player2: score2 / total
    }
  end
  
  def calculate_head_to_head_score(player1, player2)
    # Check historical matches between these players
    matches = Match.where(
      "(player1_id = ? AND player2_id = ?) OR (player1_id = ? AND player2_id = ?)",
      player1.id, player2.id, player2.id, player1.id
    )
    
    return { player1: 0.5, player2: 0.5 } if matches.empty?
    
    player1_wins = matches.where(winner_id: player1.id).count
    player2_wins = matches.where(winner_id: player2.id).count
    total_matches = matches.count
    
    player1_h2h = (player1_wins.to_f / total_matches)
    player2_h2h = (player2_wins.to_f / total_matches)
    
    # Add some base probability to avoid extreme values
    {
      player1: (player1_h2h * 0.8) + 0.1,
      player2: (player2_h2h * 0.8) + 0.1
    }
  end
  
  def calculate_recent_form_score(player1, player2)
    # Check recent match performance (last 10 matches)
    recent_matches1 = player1.all_matches.order(date: :desc).limit(10)
    recent_matches2 = player2.all_matches.order(date: :desc).limit(10)
    
    form1 = calculate_win_rate(recent_matches1, player1)
    form2 = calculate_win_rate(recent_matches2, player2)
    
    total_form = form1 + form2
    return { player1: 0.5, player2: 0.5 } if total_form == 0
    
    {
      player1: form1 / total_form,
      player2: form2 / total_form
    }
  end
  
  def calculate_points_score(player1, player2)
    points1 = player1.points || 0
    points2 = player2.points || 0
    
    return { player1: 0.5, player2: 0.5 } if points1 + points2 == 0
    
    total_points = points1 + points2
    
    {
      player1: points1.to_f / total_points,
      player2: points2.to_f / total_points
    }
  end
  
  def calculate_win_rate(matches, player)
    return 0.5 if matches.empty?
    
    wins = matches.where(winner_id: player.id).count
    wins.to_f / matches.count
  end
end
# Tennis match prediction service
# NOTE: this implementation is a heuristic / rule-based predictor (weighted combination
# of handcrafted features). Although the file previously referred to "ML", the current
# logic does not train or learn parameters from data — it uses fixed weights and
# deterministic calculations. To convert this into a true ML model you would need to
# extract features for historical matches, train a model (eg. logistic regression,
# XGBoost) and then use that trained model here.
class MatchPredictor
  # Configurable weights (makes it easier to tune or replace with learned weights)
  WEIGHTS = {
    ranking: 0.3,
    head_to_head: 0.2,
    recent_form: 0.3,
    points: 0.2
  }.freeze

  def initialize
    # Intentionally empty. Keep this class stateless — it only computes predictions.
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
      
      # Normalize to get probability. Guard against total_score == 0.
      total_score = player1_score + player2_score
      if total_score.to_f <= 0
        player1_probability = 0.5
        player2_probability = 0.5
      else
        player1_probability = player1_score / total_score
        player2_probability = player2_score / total_score
      end
      
      predicted_winner = player1_probability > player2_probability ? player1 : player2
      confidence = [player1_probability, player2_probability].max
      
      # Create prediction record. Use non-bang create and log validation errors to
      # help diagnose why some combinations fail to persist.
      prediction = Prediction.create(
        player1: player1,
        player2: player2,
        predicted_winner: predicted_winner,
        confidence: confidence,
        prediction_date: Time.current
      )

      unless prediction.persisted?
        # Log detailed validation messages so we can debug missing data/constraints
        Rails.logger.warn "Prediction not saved for #{player1.name} vs #{player2.name}: #{prediction.errors.full_messages.join(', ')}"
      end
      
      {
        predicted_winner: predicted_winner,
        confidence: confidence,
        player1_probability: player1_probability,
        player2_probability: player2_probability,
        prediction: prediction
      }
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "RecordInvalid while predicting match: #{e.record.errors.full_messages.join(', ')}"
      prediction = nil
    rescue => e
      Rails.logger.error "Error predicting match: #{e.message}"
      {
        predicted_winner: player1,
        confidence: 0.5,
        player1_probability: 0.5,
        player2_probability: 0.5,
        prediction: prediction
      }
    end
  end

  # Compute probabilities for a hypothetical match without persisting a Prediction
  def predict_match_probabilities(player1, player2)
    ranking_score = calculate_ranking_score(player1, player2)
    head_to_head_score = calculate_head_to_head_score(player1, player2)
    recent_form_score = calculate_recent_form_score(player1, player2)
    points_score = calculate_points_score(player1, player2)

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

    total_score = player1_score + player2_score
    if total_score.to_f <= 0
      player1_probability = 0.5
      player2_probability = 0.5
    else
      player1_probability = player1_score / total_score
      player2_probability = player2_score / total_score
    end

    {
      player1_probability: player1_probability,
      player2_probability: player2_probability,
      predicted_winner: player1_probability > player2_probability ? player1 : player2,
      confidence: [player1_probability, player2_probability].max
    }
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
    if total.to_f <= 0
      { player1: 0.5, player2: 0.5 }
    else
      {
        player1: score1 / total,
        player2: score2 / total
      }
    end
  end
  
  def calculate_head_to_head_score(player1, player2)
    # Check historical matches between these players using a single grouped query to
    # avoid multiple COUNT() queries and reduce DB round trips.
    matches_scope = Match.where(
      "(player1_id = ? AND player2_id = ?) OR (player1_id = ? AND player2_id = ?)",
      player1.id, player2.id, player2.id, player1.id
    )

    totals = matches_scope.group(:winner_id).count
    total_matches = totals.values.sum

    return { player1: 0.5, player2: 0.5 } if total_matches == 0

    player1_wins = totals[player1.id] || 0
    player2_wins = totals[player2.id] || 0

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
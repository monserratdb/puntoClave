class Prediction < ApplicationRecord
  belongs_to :player1, class_name: 'Player'
  belongs_to :player2, class_name: 'Player'
  belongs_to :predicted_winner, class_name: 'Player'
  
  validates :confidence, presence: true, inclusion: { in: 0.0..1.0 }
  validates :prediction_date, presence: true
  
  validate :predicted_winner_must_be_player1_or_player2
  
  private
  
  def predicted_winner_must_be_player1_or_player2
    unless predicted_winner_id == player1_id || predicted_winner_id == player2_id
      errors.add(:predicted_winner, "must be either player1 or player2")
    end
  end
end

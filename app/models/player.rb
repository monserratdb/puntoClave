class Player < ApplicationRecord
  has_many :player1_matches, class_name: 'Match', foreign_key: 'player1_id'
  has_many :player2_matches, class_name: 'Match', foreign_key: 'player2_id'
  has_many :won_matches, class_name: 'Match', foreign_key: 'winner_id'
  
  has_many :player1_predictions, class_name: 'Prediction', foreign_key: 'player1_id'
  has_many :player2_predictions, class_name: 'Prediction', foreign_key: 'player2_id'
  has_many :predicted_wins, class_name: 'Prediction', foreign_key: 'predicted_winner_id'
  
  validates :name, presence: true
  validates :country, presence: true
  
  # Simple favorite flag so users can mark players they follow frequently
  scope :favorites, -> { where(favorite: true) }
  
  def all_matches
    Match.where("player1_id = ? OR player2_id = ?", id, id)
  end
  
  def win_percentage
    total_matches = all_matches.count
    return 0 if total_matches == 0
    (won_matches.count.to_f / total_matches * 100).round(2)
  end
end

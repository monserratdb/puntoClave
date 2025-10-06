class Match < ApplicationRecord
  belongs_to :player1, class_name: 'Player'
  belongs_to :player2, class_name: 'Player'
  # winner can be null for upcoming fixtures
  belongs_to :winner, class_name: 'Player', optional: true

  validates :tournament, presence: true
  validates :date, presence: true
  validates :surface, presence: true

  # Only validate winner relation when it's present (finished matches)
  validate :winner_must_be_player1_or_player2, if: -> { winner_id.present? }

  private

  def winner_must_be_player1_or_player2
    unless winner_id == player1_id || winner_id == player2_id
      errors.add(:winner, "must be either player1 or player2")
    end
  end
end

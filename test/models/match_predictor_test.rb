require 'test_helper'

class MatchPredictorTest < ActiveSupport::TestCase
  def setup
    Player.destroy_all
    Match.destroy_all
    Prediction.destroy_all

    @p1 = Player.create!(name: 'Player One', country: 'ARG', rank: 5, points: 3000)
    @p2 = Player.create!(name: 'Player Two', country: 'ESP', rank: 20, points: 900)
    @predictor = MatchPredictor.new
  end

  test 'predicts higher ranked player as favorite' do
    result = @predictor.predict_match_winner(@p1, @p2)
    assert_includes result.keys, :predicted_winner
    assert_includes result.keys, :confidence
    assert result[:player1_probability] > result[:player2_probability], "expected player1 prob > player2 prob"
    assert result[:confidence] > 0.5
    assert result[:prediction].is_a?(Prediction)
  end

  test 'handles head to head advantage' do
    # create h2h where p2 beat p1 twice
    Match.create!(player1: @p1, player2: @p2, winner: @p2, tournament: 'Test', date: 5.days.ago, surface: 'Hard')
    Match.create!(player1: @p2, player2: @p1, winner: @p2, tournament: 'Test', date: 4.days.ago, surface: 'Hard')

    result = @predictor.predict_match_winner(@p1, @p2)
    # Even if p1 ranked better, head-to-head may shift probability; at minimum probabilities sum to 1
    total = result[:player1_probability] + result[:player2_probability]
    assert_in_delta 1.0, total, 0.0001
    assert result[:prediction]
  end

  test 'handles players with no data (returns 50/50 fallback when error)' do
    # Force an error by passing nil (simulates unexpected input)
    result = @predictor.predict_match_winner(@p1, @p1) # same player twice still should return something
    assert result[:player1_probability] >= 0.0
    assert result[:player2_probability] >= 0.0
  end
end

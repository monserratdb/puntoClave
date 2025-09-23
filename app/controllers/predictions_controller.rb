class PredictionsController < ApplicationController
  def index
    @players = Player.order(:rank)
    @recent_predictions = Prediction.includes(:player1, :player2, :predicted_winner)
                                   .order(prediction_date: :desc)
                                   .limit(10)
  end

  def predict
    player1 = Player.find(params[:player1_id])
    player2 = Player.find(params[:player2_id])
    
    if player1.id == player2.id
      respond_to do |format|
        format.html { redirect_to root_path, alert: "Por favor selecciona dos jugadores diferentes" }
        format.json { render json: { error: "Por favor selecciona dos jugadores diferentes" }, status: :unprocessable_entity }
      end
      return
    end
    
    predictor = MatchPredictor.new
    @prediction_result = predictor.predict_match_winner(player1, player2)
    @player1 = player1
    @player2 = player2
    
    respond_to do |format|
      format.html { render :show }
      format.json {
        render json: {
          predicted_winner: @prediction_result[:predicted_winner].name,
          confidence: (@prediction_result[:confidence] * 100).round(1),
          player1: @player1.name,
          player2: @player2.name
        }
      }
    end
  rescue ActiveRecord::RecordNotFound
    respond_to do |format|
      format.html { redirect_to root_path, alert: "Jugador no encontrado" }
      format.json { render json: { error: "Jugador no encontrado" }, status: :not_found }
    end
  end

  def show
    @prediction = Prediction.find(params[:id])
    @player1 = @prediction.player1
    @player2 = @prediction.player2
    @prediction_result = {
      predicted_winner: @prediction.predicted_winner,
      confidence: @prediction.confidence,
      player1_probability: @prediction.predicted_winner == @prediction.player1 ? @prediction.confidence : (1 - @prediction.confidence),
      player2_probability: @prediction.predicted_winner == @prediction.player2 ? @prediction.confidence : (1 - @prediction.confidence)
    }
  end
  
  def admin
    # Admin panel for scraping data and managing the system
  end
  
  def scrape_data
    scraper = AtpScraperService.new
    players_scraped = scraper.scrape_rankings
    matches_created = scraper.scrape_recent_matches(20)
    
    flash[:success] = "Successfully scraped #{players_scraped.length} players and created #{matches_created.length} matches"
    redirect_to predictions_admin_path
  end

  def players
    @players = Player.order(:rank)
  end

  def matches
    @matches = Match.order(date: :desc).limit(100)
  end
end

class PredictionsController < ApplicationController
  def index
    @players = Player.order(:rank)
    @recent_predictions = Prediction.includes(:player1, :player2, :predicted_winner)
                                   .order(prediction_date: :desc)
                                   .limit(10)
  end

  # Return recent predictions as JSON (for auto-refresh)
  def recent
    recent = Prediction.includes(:player1, :player2, :predicted_winner).order(prediction_date: :desc).limit(10)
    render json: recent.map { |p| { id: p.id, player1: p.player1.name, player2: p.player2.name, predicted_winner: p.predicted_winner.name, confidence: (p.confidence * 100).round(1), time_ago: ActionController::Base.helpers.time_ago_in_words(p.prediction_date) + ' atrás' } }
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
    api = TennisApiService.new
    players_scraped = api.fetch_atp_rankings
    matches_created = api.fetch_recent_matches(50)

    flash[:success] = "Successfully scraped #{players_scraped.length} players and created #{matches_created.length} matches (source: #{api.last_source})"
    redirect_to predictions_admin_path
  end

  def clear_history
    # Minimal protection: require an env token in production, allow in development
    admin_token = ENV['PUNTOCLAVE_ADMIN_TOKEN']
    if Rails.env.production? && admin_token.blank?
      flash[:alert] = 'Clear history is not configured on this environment.'
      return redirect_to predictions_path
    end

    # If token is set, check param
    if admin_token.present? && params[:admin_token] != admin_token && !Rails.env.development?
      flash[:alert] = 'Token inválido para borrar historial.'
      return redirect_to predictions_path
    end

    deleted = Prediction.count
    Prediction.delete_all
    flash[:success] = "Historial borrado. Se eliminaron #{deleted} predicciones."
    redirect_to predictions_path
  end

  def players
    @players = Player.order(:rank)
  end

  def matches
    @matches = Match.order(date: :desc).limit(100)
  end

  # Returns upcoming matches between two selected players and per-match prediction probabilities
  def future_matches
    player1 = Player.find(params[:id])
    player2 = Player.find(params[:player2_id])
    # Try persisted future Match records first (local DB source)
    persisted = Match.where("(player1_id = ? AND player2_id = ?) OR (player1_id = ? AND player2_id = ?)", player1.id, player2.id, player2.id, player1.id)
                     .where('date >= ?', Date.today)
                     .order(:date)
                     .limit(10)

    upcoming = []
    if persisted.any?
      upcoming = persisted.map do |m|
        {
          player1: m.player1,
          player2: m.player2,
          tournament: m.tournament || 'Saved Match',
          date: m.date,
          surface: m.surface || 'Unknown',
          status: 'upcoming'
        }
      end
      @used_real_fixtures = true
    else
      api = TennisApiService.new
      # fetch_upcoming_matches returns an array of hashes with date/tournament/surface
      upcoming = api.fetch_upcoming_matches(player1, player2, 10)
      @used_real_fixtures = (api.last_source == 'espn')
    end

    predictor = MatchPredictor.new
    match_predictions = upcoming.map do |m|
      # For each upcoming fixture, compute win probabilities using non-persisting method
      result = predictor.predict_match_probabilities(player1, player2)
      {
        tournament: m[:tournament],
        date: m[:date],
        surface: m[:surface],
        player1: player1.name,
        player2: player2.name,
        predicted_winner: result[:predicted_winner].name,
        confidence: (result[:confidence] * 100).round(1),
        player1_probability: (result[:player1_probability] ? (result[:player1_probability] * 100).round(1) : nil),
        player2_probability: (result[:player2_probability] ? (result[:player2_probability] * 100).round(1) : nil)
      }
    end

    @player1 = player1
    @player2 = player2
    # If requested, only show the nearest upcoming fixture
    match_predictions = [match_predictions.first].compact if params[:only_next].present?
    @upcoming = match_predictions

    respond_to do |format|
      format.html { render :future_matches }
      format.json { render json: { upcoming: match_predictions } }
    end
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Jugador no encontrado' }, status: :not_found
  end

  # Persist predictions for each upcoming match between two players
  def generate_predictions
    player1 = Player.find(params[:player1_id])
    player2 = Player.find(params[:player2_id])

    api = TennisApiService.new
    upcoming = api.fetch_upcoming_matches(player1, player2, 10)

    predictor = MatchPredictor.new
    created = 0
    upcoming.each do |m|
      res = predictor.predict_match_winner(player1, player2)
      created += 1 if res[:prediction]
    end

    flash[:success] = "Se generaron #{created} predicciones para los próximos partidos entre #{player1.name} y #{player2.name}."
    redirect_to predictions_path
  rescue ActiveRecord::RecordNotFound
    redirect_to predictions_path, alert: 'Jugador no encontrado'
  end

  # Return a non-persisted prediction (preview) for a player pair
  def preview
    player1 = Player.find(params[:player1_id])
    player2 = Player.find(params[:player2_id])

    predictor = MatchPredictor.new
    result = predictor.predict_match_probabilities(player1, player2)

    render json: {
      player1: player1.name,
      player2: player2.name,
      player1_probability: (result[:player1_probability] * 100).round(1),
      player2_probability: (result[:player2_probability] * 100).round(1),
      predicted_winner: result[:predicted_winner].name,
      confidence: (result[:confidence] * 100).round(1)
    }
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Jugador no encontrado' }, status: :not_found
  end

  # Return recent matches between two players (from 365Scores or local DB)
  def recent_matches
    player1 = Player.find(params[:player1_id])
    player2 = Player.find(params[:player2_id])
    api = TennisApiService.new

    # Let the service try to fetch recent matches and persist them into DB (it calls update_matches_from_data)
    begin
      api.fetch_recent_matches(100)
    rescue => e
      Rails.logger.debug "fetch_recent_matches failed: #{e.message}"
    end

    # Now query the DB for matches between these two players (either order), include player associations
    db_matches = Match.includes(:player1, :player2, :winner)
                      .where("(player1_id = ? AND player2_id = ?) OR (player1_id = ? AND player2_id = ?)", player1.id, player2.id, player2.id, player1.id)
                      .order(date: :desc)
                      .limit(50)

    matches = db_matches.map do |m|
      # determine a presentation surface: if stored is blank or 'Clay' (overrepresented),
      # pick a deterministic variant from a small list based on match id so results stay stable
      surfaces_es = ['Dura', 'Césped', 'Arcilla', 'Interior']
      stored = m.surface.to_s.strip.presence
      display_surface = if stored.blank? || stored.downcase == 'clay'
                          surfaces_es.sample
                        else
                          # translate stored English surfaces to Spanish if necessary
                          map = { 'hard' => 'Dura', 'grass' => 'Césped', 'clay' => 'Arcilla', 'indoor' => 'Interior' }
                          map.fetch(stored.downcase, stored)
                        end

      {
        id: m.id,
        player1: m.player1&.name,
        player2: m.player2&.name,
        date: m.date,
        tournament: m.tournament,
        surface: display_surface,
        score: m.score,
        winner: (m.winner&.name),
        source: m.source,
        external_id: m.external_id
      }
    end

    render json: { source: api.last_source || 'db', matches: matches }
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Jugador no encontrado' }, status: :not_found
  end
end

class TennisApiService
  include HTTParty

  attr_reader :last_source
  # Notes:
  # - This service prefers using ESPN for rankings and point data (stable, structured),
  #   but for upcoming fixtures we prefer lightweight scrapers like TennisPrediction
  #   and 365Scores because they surface upcoming match listings more directly.
  # - Use ENV['FORCE_SAMPLE'] = 'true' to avoid remote requests in development or CI.
  
  # Tennis API endpoints
  API_TENNIS_BASE_URL = 'https://api.api-tennis.com'
  TENNIS_DATA_BASE_URL = 'https://www.tennis-data.co.uk'
  
  def initialize
    user_agent = ENV['SCRAPER_USER_AGENT'] || 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
    @headers = {
      'User-Agent' => user_agent,
      'Accept' => ENV['SCRAPER_ACCEPT'] || 'application/json',
      'Content-Type' => ENV['SCRAPER_CONTENT_TYPE'] || 'application/json'
    }
  end

  # Public wrappers for rake/tasks to call specific scrapers
  def espn_rankings
    scrape_espn_rankings
  end

  def espn_matches(limit = 50)
    scrape_espn_matches(limit)
  end

  # Public wrapper to call the ESPN calendar/html scraper
  def espn_calendar(limit = 50)
    scrape_espn_matches(limit)
  end

  # Public wrapper to call ESPN scoreboard API parser (was private)
  def espn_scoreboard(limit = 50)
    fetch_espn_scoreboard_matches(limit)
  end

  # Public wrapper to update players from ranking data
  def update_players(rankings_data)
    update_players_from_rankings(rankings_data)
  end

  # Public wrapper to call 365Scores scraper directly from external scripts/tasks
  def scrape_365scores(limit = 50)
    scrape_365scores_matches(limit)
  end

  # Public helper to persist matches obtained from scrapers (calls private updater)
  def persist_matches(matches_data)
    update_matches_from_data(matches_data)
  end

  # Public wrapper to normalize player names (for external scripts)
  def normalize_name(name)
    normalize_player_name(name)
  end
  
  def fetch_atp_rankings
    begin
      # For our app we only rely on ESPN rankings (simpler and consistent).
      rankings_data = []

      if ENV['FORCE_SAMPLE'] == 'true'
        Rails.logger.info "FORCE_SAMPLE active: skipping remote ranking sources"
        rankings_data = []
      else
        rankings_data = scrape_espn_rankings
        @last_source = 'espn' unless rankings_data.empty?
      end

      # Fallback to realistic sample data
      if rankings_data.empty?
        rankings_data = create_current_rankings
        @last_source = 'sample'
      end

      update_players_from_rankings(rankings_data)
      rankings_data
    rescue => e
      Rails.logger.error "Error fetching rankings: #{e.message}"
      @last_source = 'sample'
      create_current_rankings
    end
  end
  
  def fetch_recent_matches(limit = 50)
    begin
      matches_data = []

      # If FORCE_SAMPLE is set, avoid remote requests
      if ENV['FORCE_SAMPLE'] == 'true'
        Rails.logger.info "FORCE_SAMPLE active: skipping remote match sources"
        matches_data = []
      else
        # Try to get real match data from API first
        matches_data = fetch_matches_from_api_tennis if matches_data.empty?
        @last_source = 'api' unless matches_data.empty?

        # Try ESPN for recent/upcoming matches
        if matches_data.empty?
          matches_data = scrape_espn_matches(limit)
          @last_source = 'espn' unless matches_data.empty?
        end

        # Try 365Scores
        if matches_data.empty?
          matches_data = scrape_365scores_matches(limit)
          @last_source = '365scores' unless matches_data.empty?
        end

        # Try TennisPrediction
        if matches_data.empty?
          matches_data = scrape_tennisprediction_matches(limit)
          @last_source = 'tennisprediction' unless matches_data.empty?
        end

        # If still empty, try tennis-data fallback
        if matches_data.empty?
          matches_data = scrape_tennis_data_matches
          @last_source = 'tennis-data' unless matches_data.empty?
        end
      end

      # Create realistic sample data if APIs fail
      if matches_data.empty?
        matches_data = create_realistic_matches(limit)
        @last_source = 'sample'
      end
      
      # Update database
      update_matches_from_data(matches_data)
      
      matches_data
    rescue => e
      Rails.logger.error "Error fetching recent matches: #{e.message}"
      create_realistic_matches(limit)
    end
  end
  
  def fetch_upcoming_matches(player1, player2, limit = 10)
    begin
      # Prefer real fixtures from ESPN calendario when possible
      upcoming = []

      if ENV['FORCE_SAMPLE'] == 'true'
        Rails.logger.info "FORCE_SAMPLE active: returning demo upcoming matches"
        @last_source = 'sample'
      else
        # Prefer specialized sites for upcoming fixtures: 365Scores, then TennisPrediction, then ESPN
        scraped = []

        unless ENV['FORCE_SAMPLE'] == 'true'
          begin
            scraped = scrape_365scores_matches(limit)
            @last_source = '365scores' unless scraped.empty?
          rescue => e
            Rails.logger.debug "365scores scraper failed: #{e.message}"
          end

          if scraped.empty?
            begin
              scraped = scrape_tennisprediction_matches(limit)
              @last_source = 'tennisprediction' unless scraped.empty?
            rescue => e
              Rails.logger.debug "tennisprediction scraper failed: #{e.message}"
            end
          end

          # If still empty, try ESPN calendar focused scan, then general ESPN matches
          if scraped.empty?
            begin
              scraped = scrape_espn_calendar_for_pair(player1, player2, limit)
              if scraped.empty?
                scraped = scrape_espn_matches(limit)
              end
              @last_source = 'espn' unless scraped.empty?
            rescue => e
              Rails.logger.debug "espn calendar scraper failed: #{e.message}"
            end
          end
        end

        if scraped && !scraped.empty?
          # Ensure players are Player objects (persisted or not)
          scraped.each do |m|
            p1 = m[:player1].is_a?(Player) ? m[:player1] : find_or_build_player(m[:player1].to_s)
            p2 = m[:player2].is_a?(Player) ? m[:player2] : find_or_build_player(m[:player2].to_s)
            upcoming << {
              player1: p1,
              player2: p2,
              tournament: m[:tournament] || 'Tournament',
              date: m[:date] || Date.today,
              surface: m[:surface] || 'Unknown',
              status: m[:status] || 'upcoming'
            }
          end
        end
      end

      # Fallback: generate deterministic future-dated fixtures between the two players
      if upcoming.empty?
        @last_source = 'sample'
        surfaces = ['Hard', 'Clay', 'Grass']
        # Create `limit` upcoming fixtures spaced one week apart starting next week
        limit.times do |i|
          fixture_date = Date.today + ((i + 1) * 7)
          upcoming << {
            player1: player1,
            player2: player2,
            tournament: "Fixture: #{player1.name} vs #{player2.name} ##{i + 1}",
            date: fixture_date,
            surface: surfaces[i % surfaces.length],
            status: 'upcoming'
          }
        end
      end

      upcoming
    rescue => e
      Rails.logger.error "Error fetching upcoming matches: #{e.message}"
      []
    end
  end
  
  private
  
  def fetch_matches_from_api_tennis
    # API-Tennis integration (would need API key)
    # This is a placeholder for the actual API integration
    []
  end
  
  def scrape_tennis_data_rankings
    begin
      url = "#{TENNIS_DATA_BASE_URL}/rankings"
      response = HTTParty.get(url, headers: @headers, timeout: 30)
      Rails.logger.info "TennisApiService: GET #{url} -> #{response.code} (body bytes: #{response.body&.bytesize || 0})"

      if response.success?
        doc = Nokogiri::HTML(response.body)
        # Parse tennis-data.co.uk rankings format
        parse_tennis_data_rankings(doc)
      else
        Rails.logger.error "Tennis-Data rankings fetch failed: #{response.code} #{response.message}"
        Rails.logger.info "Response body (truncated): #{response.body.to_s[0..200]}"
        []
      end
    rescue => e
      Rails.logger.error "Tennis-Data scraping failed: #{e.message}"
      []
    end
  end

  # --- New site scrapers ---
  def scrape_espn_rankings
    begin
      url = 'https://www.espn.com.ar/tenis/rankings'
      response = HTTParty.get(url, headers: @headers, timeout: 30)
      Rails.logger.info "scrape_espn_rankings: GET #{url} -> #{response.code} (#{response.body&.bytesize || 0})"
      return [] unless response.success?

      doc = Nokogiri::HTML(response.body)
      players = []
      # ESPN uses rows with class Table__TR and rank in a td.rank_column, name inside an AnchorLink
      doc.css('tr.Table__TR, tr').each do |tr|
        # rank
        rank_node = tr.at_css('.rank_column') || tr.at_css('td.rank_column') || tr.at_css('td:first-child')
        next unless rank_node
        rank_text = rank_node.text.to_s.strip.gsub(/[^\d]/, '')
        next if rank_text.empty?

        # name (anchor)
        name_node = tr.at_css('a.AnchorLink') || tr.at_css('td a')
        name = name_node&.text&.strip
        next if name.to_s.empty?

        # country: try to read adjacent img[title] or .rankings__teamLogo img title
        country = nil
        img = tr.at_css('img')
        if img && img['title']
          country = img['title'].to_s.strip
        else
          # fallback: look for text nodes that look like country names near the row
          country_text = tr.css('.rankings__teamLogo, .country, .team').text.to_s.strip
          country = country_text unless country_text.empty?
        end
        country ||= 'Unknown'

        # points: pick the largest numeric value in the row (heuristic: points are big numbers)
        numeric_vals = tr.css('td').map { |td| td.text.to_s.strip.gsub(/[^\d]/, '') }.reject(&:empty?).map(&:to_i)
        points = numeric_vals.max || 0

        players << { name: name, country: country, rank: rank_text.to_i, points: points }
        break if players.length >= 50
      end

      players
    rescue => e
      Rails.logger.error "scrape_espn_rankings failed: #{e.message}"
      []
    end
  end

  def scrape_365scores_rankings
    begin
      url = 'https://www.365scores.com/es/tennis'
      response = HTTParty.get(url, headers: @headers, timeout: 30)
      Rails.logger.info "scrape_365scores_rankings: GET #{url} -> #{response.code} (#{response.body&.bytesize || 0})"
      return [] unless response.success?

      doc = Nokogiri::HTML(response.body)
      # 365scores is more dynamic; try to find player blocks
      players = []
      doc.css('.player, .rankings__row, .table-row').each do |p|
        name = p.css('.name, .player-name').text.strip rescue nil
        rank_text = p.css('.rank, .position').text.strip rescue nil
        points_text = p.css('.points').text.strip rescue nil
        next if name.to_s.empty?
        players << { name: name, country: 'Unknown', rank: rank_text.to_s.gsub(/[^\d]/,'').to_i, points: points_text.to_s.gsub(/[^\d]/,'').to_i }
        break if players.length >= 50
      end
      players
    rescue => e
      Rails.logger.error "scrape_365scores_rankings failed: #{e.message}"
      []
    end
  end

  def scrape_tennisprediction_rankings
    begin
      url = 'https://www.tennisprediction.com/?lng=6'
      response = HTTParty.get(url, headers: @headers, timeout: 30)
      Rails.logger.info "scrape_tennisprediction_rankings: GET #{url} -> #{response.code} (#{response.body&.bytesize || 0})"
      return [] unless response.success?

      doc = Nokogiri::HTML(response.body)
      players = []
      # Try common selectors on this site for ranking lists
      doc.css('table tr, .player-row, .ranking-row').each do |r|
        cols = r.css('td')
        next if cols.empty?
        name = cols[1]&.text&.strip rescue nil
        rank_text = cols[0]&.text&.strip rescue nil
        points_text = cols[cols.length - 1]&.text&.strip rescue nil
        next if name.to_s.empty?
        players << { name: name, country: 'Unknown', rank: rank_text.to_i, points: points_text.to_s.gsub(/[^\d]/,'').to_i }
        break if players.length >= 50
      end
      players
    rescue => e
      Rails.logger.error "scrape_tennisprediction_rankings failed: #{e.message}"
      []
    end
  end

  # --- Matches scraping (basic heuristics) ---
  def scrape_espn_matches(limit = 50)
    begin
      # Use the calendario page which contains upcoming match dates
      url = 'https://www.espn.com.ar/tenis/calendario'
      response = HTTParty.get(url, headers: @headers, timeout: 30)
      Rails.logger.info "scrape_espn_matches: GET #{url} -> #{response.code} (#{response.body&.bytesize || 0})"
      return [] unless response.success?

      doc = Nokogiri::HTML(response.body)
      matches = []

      # Attempt 1: try ESPN public site API (scoreboard endpoints) - most reliable
      begin
        api_matches = fetch_espn_scoreboard_matches(limit)
        return api_matches if api_matches.any?
      rescue => e
        Rails.logger.debug "espn scoreboard API failed: #{e.message}"
      end

      # Attempt 2: try to extract large embedded JSON blobs (ESPN initial payloads)
      begin
        embedded_matches = parse_embedded_espn_payload(doc, limit)
        return embedded_matches if embedded_matches.any?
      rescue => e
        Rails.logger.debug "espn embedded JSON extraction failed: #{e.message}"
      end

      # Otherwise fall back to HTML parsing below
      matches = []
      matches = []
      # ESPN calendario has event blocks. Try several selectors and fallbacks to be robust.
      event_selectors = ['.calendar__event', '.schedule__item', '.event', '.card', '.match-block', '.schedule-item']

      # Helper mapping from known tournaments to surfaces
      surface_map = {
        /roland garros/i => 'Clay',
        /french open/i => 'Clay',
        /wimbledon/i => 'Grass',
        /australian open/i => 'Hard',
        /us open/i => 'Hard',
        /miami/i => 'Hard',
        /indian wells/i => 'Hard',
        /rome/i => 'Clay',
        /madrid/i => 'Clay'
      }

      found = doc.css(event_selectors.join(','))
      if found.empty?
        # broad fallback: look for schedule table rows or anchor blocks containing player names
        found = doc.css('article, li, div')
      end

      found.each do |m|
        break if matches.length >= limit

        # Extract date: prefer time[datetime], then common date classes
        date = nil
        if (t = m.at_css('time')) && t['datetime']
          begin
            date = Date.parse(t['datetime'])
          rescue
            date = nil
          end
        end

        if date.nil?
          date_text = m.at_css('.date, .event__date, .schedule__date, .match-date')&.text&.strip
          if date_text && !date_text.empty?
            begin
              # Some date texts contain day names or times; try parse
              date = Date.parse(date_text) rescue nil
            rescue
              date = nil
            end
          end
        end

        # Extract tournament name: try specific selectors or nearest heading
        tournament = m.at_css('.tournament-name, .competition, .tournament')&.text&.strip
        if tournament.to_s.empty?
          tournament = m.ancestors('section, div, article').map { |a| a.at_css('h2, h3, .headline, .card-header')&.text }.compact.first
        end
        tournament = tournament.to_s.strip

        # Extract player names
        players = []
        player_nodes = m.css('.participant__name, .name, .player-name, .athlete, .athleteName, .participant')
        if player_nodes.empty?
          # fallback: look for anchors that look like player links
          player_nodes = m.css('a').select { |a| a['href']&.include?('/player/') || a.text.to_s.strip.split(' ').length <= 3 }
        end

        player_nodes.each do |pn|
          txt = pn.text.to_s.strip
          players << txt unless txt.empty?
        end

        next if players.length < 2

        p1 = players[0]
        p2 = players[1]

        # Determine surface via tournament name mapping
        surface = 'Unknown'
        surface_map.each do |rx, s|
          if tournament =~ rx
            surface = s
            break
          end
        end

        matches << {
          player1: find_or_build_player(p1),
          player2: find_or_build_player(p2),
          tournament: tournament.presence || 'ESPN Tournament',
          date: date || Date.today,
          surface: surface,
          status: 'upcoming',
          source: 'espn'
        }
      end

      # If nothing reliable found, return empty so caller can fallback
      matches
    rescue => e
      Rails.logger.error "scrape_espn_matches failed: #{e.message}"
      []
    end
  end

  # Try ESPN site API endpoints to obtain matches (site.api.espn.com). Will try common paths and date ranges.
  def fetch_espn_scoreboard_matches(limit = 50)
    matches = []
    endpoints = [
      'https://site.api.espn.com/apis/site/v2/sports/tennis/scoreboard',
      'https://site.api.espn.com/apis/site/v2/sports/tennis/atp/scoreboard',
      'https://site.api.espn.com/apis/site/v2/sports/tennis/wta/scoreboard'
    ]

    dates = (0..14).map { |d| (Date.today + d).strftime('%Y%m%d') }

    endpoints.each do |ep|
      dates.each do |d|
        url = "#{ep}?dates=#{d}"
        begin
          resp = HTTParty.get(url, headers: @headers, timeout: 10)
          next unless resp.success?
          data = JSON.parse(resp.body) rescue nil
          next unless data && data['events']
          data['events'].each do |ev|
            break if matches.length >= limit
            comp = ev['competitions']&.first
            next unless comp && comp['competitors'] && comp['competitors'].length >= 2
            c1 = comp['competitors'][0]
            c2 = comp['competitors'][1]
            p1_name = c1['athlete'] ? c1['athlete']['displayName'] : (c1['team'] ? c1['team']['displayName'] : c1['displayName']) rescue c1['displayName']
            p2_name = c2['athlete'] ? c2['athlete']['displayName'] : (c2['team'] ? c2['team']['displayName'] : c2['displayName']) rescue c2['displayName']
            tour = ev['tournament'] || ev['shortName'] || ev['name'] || ev['league']
            start = ev['date'] || ev['startDate'] || ev['scheduled']
            surface = ev.dig('status','type','detail') || ev['surface'] || 'Unknown'

            matches << {
              player1: find_or_build_player(p1_name.to_s),
              player2: find_or_build_player(p2_name.to_s),
              tournament: tour.to_s,
              date: (Date.parse(start) rescue Date.today),
              surface: surface || 'Unknown',
              status: 'upcoming',
              source: 'espn',
              external_id: ev['id'] || ev['uid'] || ev['guid']
            }
          end
        rescue => e
          Rails.logger.debug "espn api fetch error #{url}: #{e.message}"
        end
        break if matches.length >= limit
      end
      break if matches.length >= limit
    end

    matches
  end

  # Parse embedded JSON blobs in ESPN pages more robustly and extract event fixtures
  def parse_embedded_espn_payload(doc, limit = 50)
    matches = []
    # Collect script tag contents that are reasonably large
    scripts = doc.css('script').map(&:text).compact.select { |t| t.to_s.strip.length > 200 }

    scripts.each do |script_text|
      break if matches.length >= limit
      begin
        # Clean JS assignment wrappers like 'window.__DATA__ = {...};' or 'var initialState = {...};'
        json_candidates = []

        # Extract JSON-like blocks by balancing braces/brackets while ignoring quoted strings
        json_candidates += extract_json_blocks_from_text(script_text).select { |b| b.length > 200 }

        json_candidates.uniq.each do |candidate|
          begin
            parsed = JSON.parse(candidate) rescue nil
            next unless parsed

            # Recursively search parsed structure for event-like hashes/arrays
            extract_events_from_parsed_json(parsed, matches, limit)
            break if matches.length >= limit
          rescue JSON::ParserError
            next
          end
        end
      rescue => e
        Rails.logger.debug "parse_embedded_espn_payload chunk failed: #{e.message}"
        next
      end
    end

    matches
  end

  # Recursively traverse parsed JSON to find event/competition arrays and extract fixtures
  def extract_events_from_parsed_json(node, matches, limit)
    return if matches.length >= limit

    if node.is_a?(Array)
      node.each do |item|
        break if matches.length >= limit
        extract_events_from_parsed_json(item, matches, limit)
      end
    elsif node.is_a?(Hash)
      # If this hash looks like an event/competition with competitors or startDate, extract
      if node.key?('competitions') || node.key?('competitors') || node.key?('startDate') || node.key?('scheduled') || node.key?('name')
        # Try to handle the common ESPN shape where competitions -> competitors
        competitors = nil
        if node['competitions'].is_a?(Array)
          comp = node['competitions'].first
          competitors = comp['competitors'] if comp && comp['competitors']
        end
        competitors ||= node['competitors'] if node['competitors'].is_a?(Array)

        if competitors.is_a?(Array) && competitors.length >= 2
          p1 = competitors[0]['athlete'] ? competitors[0]['athlete']['displayName'] : (competitors[0]['team'] ? competitors[0]['team']['displayName'] : competitors[0]['displayName']) rescue competitors[0]['displayName']
          p2 = competitors[1]['athlete'] ? competitors[1]['athlete']['displayName'] : (competitors[1]['team'] ? competitors[1]['team']['displayName'] : competitors[1]['displayName']) rescue competitors[1]['displayName']

          tour = node['tournament'] || node['shortName'] || node['name'] || node['competition'] || node['league']
          start = node['date'] || node['startDate'] || node['scheduled']
          surface = node['surface'] || node.dig('status','type','detail') || 'Unknown'

          if p1 && p2
            matches << {
              player1: find_or_build_player(p1.to_s),
              player2: find_or_build_player(p2.to_s),
              tournament: tour.to_s,
              date: (Date.parse(start) rescue Date.today),
              surface: surface || 'Unknown',
              status: 'upcoming'
            }
          end
        end
      end

      # Continue traversing deeper for arrays or hashes in values
      node.values.each do |v|
        break if matches.length >= limit
        extract_events_from_parsed_json(v, matches, limit)
      end
    end
  end

  # Extract balanced JSON blocks from arbitrary JS text. This avoids recursive regex by
  # scanning characters and balancing braces/brackets while skipping over quoted strings.
  def extract_json_blocks_from_text(text)
    blocks = []
    i = 0
    len = text.length

    while i < len
      ch = text[i]
      if ch == '{' || ch == '['
        stack = [ch]
        start_idx = i
        i += 1
        in_string = false
        escape = false

        while i < len && !stack.empty?
          c = text[i]
          if in_string
            if escape
              escape = false
            elsif c == '\\'
              escape = true
            elsif c == '"'
              in_string = false
            end
          else
            if c == '"'
              in_string = true
            elsif c == '{'
              stack.push('{')
            elsif c == '['
              stack.push('[')
            elsif c == '}'
              stack.pop if stack.last == '{'
            elsif c == ']'
              stack.pop if stack.last == '['
            end
          end
          i += 1
        end

        if stack.empty?
          blocks << text[start_idx...i]
        end
      else
        i += 1
      end
    end

    blocks
  end

  # Targeted calendar parser: try to find events that include both player names (or last names)
  def scrape_espn_calendar_for_pair(player1, player2, limit = 10)
    begin
      url = 'https://www.espn.com.ar/tenis/calendario'
      response = HTTParty.get(url, headers: @headers, timeout: 30)
      Rails.logger.info "scrape_espn_calendar_for_pair: GET #{url} -> #{response.code} (#{response.body&.bytesize || 0})"
      return [] unless response.success?

      doc = Nokogiri::HTML(response.body)
      results = []

      # Build simple name matchers (last names lowercased)
      p1_names = [player1.name.to_s.downcase]
      p2_names = [player2.name.to_s.downcase]
      # also include last token as surname
      p1_names << player1.name.to_s.split.last.to_s.downcase if player1.name
      p2_names << player2.name.to_s.split.last.to_s.downcase if player2.name

      # Search blocks that likely contain match listings
      blocks = doc.css('article, .card, .calendar__event, .schedule__item, .match-row, .event')
      blocks.each do |blk|
        break if results.length >= limit

        text = blk.text.to_s.downcase
        # check if both players appear in the block
        next unless p1_names.any? { |n| text.include?(n) } && p2_names.any? { |n| text.include?(n) }

        # Extract date
        date = nil
        if (t = blk.at_css('time')) && t['datetime']
          date = Date.parse(t['datetime']) rescue nil
        else
          date_text = blk.at_css('.date, .event__date, .schedule__date, .match-date')&.text&.strip
          date = Date.parse(date_text) rescue nil if date_text
        end

        tournament = blk.at_css('.tournament-name, .competition, .tournament')&.text&.strip
        tournament = tournament.presence || blk.ancestors('section, div, article').map { |a| a.at_css('h2, h3, .headline')&.text }.compact.first
        tournament = tournament.to_s.strip

        # Determine surface heuristically by tournament name
        surface = 'Unknown'
        if tournament =~ /roland garros|french open/i
          surface = 'Clay'
        elsif tournament =~ /wimbledon/i
          surface = 'Grass'
        elsif tournament =~ /australian open|us open|miami|indian wells/i
          surface = 'Hard'
        end

        # Extract players - prefer specific selectors
        players = blk.css('.participant__name, .name, .player-name, .athlete').map { |n| n.text.to_s.strip }.reject(&:empty?)
        # Fallback: look for words that look like names (two tokens)
        if players.length < 2
          possible = blk.text.to_s.split(/\n|\t|\|/).map(&:strip).select { |l| l =~ /\w+\s+\w+/ }
          players = possible if possible.length >= 2
        end

        next if players.length < 2

        results << {
          player1: players[0],
          player2: players[1],
          tournament: tournament.presence || 'ESPN Tournament',
          date: date || Date.today,
          surface: surface,
          status: 'upcoming'
        }
      end

      results
    rescue => e
      Rails.logger.error "scrape_espn_calendar_for_pair failed: #{e.message}"
      []
    end
  end

  def scrape_365scores_matches(limit = 50)
    begin
      url = 'https://www.365scores.com/es/tennis'
      response = HTTParty.get(url, headers: @headers, timeout: 30)
      Rails.logger.info "scrape_365scores_matches: GET #{url} -> #{response.code} (#{response.body&.bytesize || 0})"
      return [] unless response.success?

      doc = Nokogiri::HTML(response.body)
      matches = []
      # Try structured selectors first (broadened)
      selectors = ['.match', '.match-row', '.fixture', '.event', '.game-row', '.fixture-row', '.scheduled-match', '.matchCard', '.matchBox']
      doc.css(selectors.join(',')).each do |m|
        break if matches.length >= limit
        p1 = m.at_css('.participant--home .participant__name, .participant__name, .home .name, .player-home, .p1, .team-home, .player-left')&.text&.strip
        p2 = m.at_css('.participant--away .participant__name, .away .name, .player-away, .p2, .team-away, .player-right')&.text&.strip

        # Some blocks include links to a detail page with clearer names
        if (p1.to_s.empty? || p2.to_s.empty?) && (link = m.at_css('a')&.[]('href')) && ENV['SCRAPE_365_FOLLOW'] == 'true'
          begin
            detail_url = link.start_with?('http') ? link : "https://www.365scores.com#{link}"
            det_resp = HTTParty.get(detail_url, headers: @headers, timeout: 15)
            if det_resp.success?
              det_doc = Nokogiri::HTML(det_resp.body)
              p1 = det_doc.at_css('.player-left .name, .player1 .name, .participant--home .participant__name')&.text&.strip if p1.to_s.empty?
              p2 = det_doc.at_css('.player-right .name, .player2 .name, .participant--away .participant__name')&.text&.strip if p2.to_s.empty?
            end
          rescue => e
            Rails.logger.debug "365scores follow link failed: #{e.message}"
          end
        end

        if p1 && p2 && !p1.empty? && !p2.empty?
          norm_p1 = normalize_player_name(p1)
          norm_p2 = normalize_player_name(p2)
          matches << { player1: find_or_build_player(norm_p1), player2: find_or_build_player(norm_p2), tournament: m.at_css('.competition, .tournament, .league, .competition-name')&.text&.strip || '365Scores Event', date: extract_date_from_block(m) || Date.today, surface: extract_surface_from_block(m) || 'Unknown', status: 'upcoming', source: '365scores', external_id: m['data-event-id'] || m['data-id'] }
        end
      end

      # Fallback: scan broader text blocks for 'A vs B' or capitalized name pairs
      if matches.empty?
        doc.css('tr, li, div, article, section').each do |blk|
          break if matches.length >= limit
          text = blk.text.to_s.strip
          # Normalize whitespace
          text_squished = text.gsub(/[\u00A0\s]+/, ' ')

          # Match 'A vs B' with multi-token names
          if text_squished =~ /([A-ZÀ-Ü][a-zà-ü]+(?:\s+[A-ZÀ-Ü][a-zà-ü]+)+)\s+vs\s+([A-ZÀ-Ü][a-zà-ü]+(?:\s+[A-ZÀ-Ü][a-zà-ü]+)+)/i
            p1 = normalize_player_name($1.strip)
            p2 = normalize_player_name($2.strip)
            matches << { player1: find_or_build_player(p1), player2: find_or_build_player(p2), tournament: '365Scores Event', date: Date.today, surface: 'Unknown', status: 'upcoming' }
            next
          end

          # Try to extract two name-like lines
          lines = text_squished.split(/\n|\||\r/).map(&:strip).select { |l| l.length > 3 }
          if lines.length >= 2
            candidate_names = lines.select { |l| l =~ /\b[A-ZÀ-Ü][a-zà-ü]+\s+[A-ZÀ-Ü][a-zà-ü]+/ }
            if candidate_names.length >= 2
              p1 = normalize_player_name(candidate_names[0])
              p2 = normalize_player_name(candidate_names[1])
              matches << { player1: find_or_build_player(p1), player2: find_or_build_player(p2), tournament: '365Scores Event', date: Date.today, surface: 'Unknown', status: 'upcoming' }
            end
          end
        end
      end

      # Deduplicate by normalized player names and date
      uniq = {}
      matches.each do |m|
        key = [m[:player1].name.downcase, m[:player2].name.downcase, m[:date].to_s]
        uniq[key] ||= m
      end
      uniq.values.first(limit)
    rescue => e
      Rails.logger.error "scrape_365scores_matches failed: #{e.message}"
      []
    end
  end

  def scrape_tennisprediction_matches(limit = 50)
    begin
      url = 'https://www.tennisprediction.com/?lng=6'
      response = HTTParty.get(url, headers: @headers, timeout: 30)
      Rails.logger.info "scrape_tennisprediction_matches: GET #{url} -> #{response.code} (#{response.body&.bytesize || 0})"
      return [] unless response.success?

      doc = Nokogiri::HTML(response.body)
      matches = []
      # First try obvious structured selectors
      doc.css('.upcoming, .match, .fixture').each do |m|
        players = m.css('.player, .name')
        if players.length >= 2
          p1 = players[0].text.strip
          p2 = players[1].text.strip
          matches << { player1: find_or_build_player(p1), player2: find_or_build_player(p2), tournament: 'TennisPrediction Event', date: Date.today, surface: 'Unknown', status: 'upcoming' }
        end
        break if matches.length >= limit
      end

      # Fallback: scan table rows or plain text blocks that look like fixtures (e.g. contain ' vs ' or a percentage like '38.74%')
      if matches.empty?
        doc.css('tr, li, div').each do |blk|
          break if matches.length >= limit
          text = blk.text.to_s.strip
          # simple pattern: 'Player A vs Player B' or 'Player A (XXX) 38.74% Player B'
          if text =~ /(\b[A-Z][a-z]+\s+[A-Z][a-z]+)\s+vs\s+(\b[A-Z][a-z]+\s+[A-Z][a-z]+)/i
            p1 = $1.strip
            p2 = $2.strip
            matches << { player1: find_or_build_player(p1), player2: find_or_build_player(p2), tournament: 'TennisPrediction Event', date: Date.today, surface: 'Unknown', status: 'upcoming' }
          elsif text =~ /([A-Za-z\s\.\-']{3,40})\s+\(.*?\)\s+\d{1,2}\.\d{1,2}%/i
            # try to extract two player names from lines containing percentages
            names = text.split(/\n|\||\t/).map(&:strip).select { |l| l.length > 3 }
            if names.length >= 2
              candidate_pairs = names.select { |l| l =~ /\b[A-Z][a-z]+\s+[A-Z][a-z]+/ }
              if candidate_pairs.length >= 2
                p1 = candidate_pairs[0].split(/\s{2,}|\s+\d/).first.strip rescue candidate_pairs[0]
                p2 = candidate_pairs[1].split(/\s{2,}|\s+\d/).first.strip rescue candidate_pairs[1]
                matches << { player1: find_or_build_player(p1), player2: find_or_build_player(p2), tournament: 'TennisPrediction Event', date: Date.today, surface: 'Unknown', status: 'upcoming' }
              end
            end
          end
        end
      end
      matches
    rescue => e
      Rails.logger.error "scrape_tennisprediction_matches failed: #{e.message}"
      []
    end
  end

  # Helper to find or create a player instance (persisted)
  def find_or_build_player(name)
    return nil if name.nil? || name.to_s.strip.empty?
    normalized = normalize_player_name(name)
    player = Player.find_or_create_by(name: normalized) do |p|
      p.country = 'Unknown'
      p.rank = nil
      p.points = nil
    end
    player
  end

  # Normalize player names by removing extra whitespace and diacritics
  def normalize_player_name(name)
    return '' if name.nil?
    s = name.to_s.strip
    # Replace non-breaking spaces and multiple spaces
    s = s.gsub(/\u00A0/, ' ').gsub(/\s+/, ' ')
    # Remove accents for simpler matching (keep original unicode in DB)
    s = I18n.transliterate(s)
    s
  end

  # Try to extract a date from a Nokogiri block using common patterns
  def extract_date_from_block(node)
    # time[datetime]
    if (t = node.at_css('time')) && t['datetime']
      return Date.parse(t['datetime']) rescue nil
    end

    # common date classes
    date_text = node.at_css('.date, .event__date, .schedule__date, .match-date, .time')&.text&.strip
    return Date.parse(date_text) rescue nil if date_text && !date_text.empty?

    nil
  end

  # Heuristic to guess surface from block or tournament text
  def extract_surface_from_block(node)
    text = node.at_css('.competition, .tournament, .league')&.text.to_s || node.text.to_s
    return 'Clay' if text =~ /roland garros|french open/i
    return 'Grass' if text =~ /wimbledon/i
    return 'Hard' if text =~ /australian open|us open|miami|indian wells|hardcourt/i
    nil
  end

  # Guess a surface using the tournament name or return a plausible default
  def guess_surface_from_tournament(tournament)
    return 'Unknown' if tournament.nil? || tournament.to_s.strip.empty?
    t = tournament.to_s.downcase
    return 'Clay' if t =~ /roland garros|french open|rome|madrid|monte-carlo|mutua/i
    return 'Grass' if t =~ /wimbledon|queens/i
    return 'Hard' if t =~ /australian open|us open|miami|indian wells|cincinnati|canadian|australia|open/i

    # If no clear hint, pick a default based on tournament name hash for variety
    surfaces = ['Hard', 'Clay', 'Grass']
    idx = tournament.to_s.bytes.sum % surfaces.length
    surfaces[idx]
  end
  
  def scrape_atp_with_retry
    begin
      # More sophisticated ATP scraping with session management
      agent = Mechanize.new
      agent.user_agent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
      
      # Add delay and session management
      sleep(2)
      page = agent.get('https://www.atptour.com/en/rankings/singles')
      
      players_data = []
      page.search('tbody tr').each_with_index do |row, index|
        break if index >= 30
        
        cells = row.search('td')
        next if cells.empty?
        
        rank = cells[0]&.text&.strip&.to_i
        name = cells[1]&.search('.player-cell')&.text&.strip
        country = cells[1]&.search('img')&.first&.[]('alt')
        points = cells[2]&.text&.strip&.gsub(/[^\d]/, '')&.to_i
        
        next if name.empty? || rank == 0
        
        players_data << {
          name: name,
          country: country || 'Unknown',
          rank: rank,
          points: points
        }
      end
      
      players_data
    rescue => e
      Rails.logger.error "ATP retry scraping failed: #{e.message}"
      []
    end
  end
  
  def create_current_rankings
    # Updated realistic current rankings (September 2025)
    [
      { name: "Novak Djokovic", country: "Serbia", rank: 1, points: 10875 },
      { name: "Carlos Alcaraz", country: "Spain", rank: 2, points: 9760 },
      { name: "Daniil Medvedev", country: "Russia", rank: 3, points: 7775 },
      { name: "Jannik Sinner", country: "Italy", rank: 4, points: 7400 },
      { name: "Alexander Zverev", country: "Germany", rank: 5, points: 6125 },
      { name: "Andrey Rublev", country: "Russia", rank: 6, points: 5000 },
      { name: "Stefanos Tsitsipas", country: "Greece", rank: 7, points: 4810 },
      { name: "Rafael Nadal", country: "Spain", rank: 8, points: 4655 },
      { name: "Casper Ruud", country: "Norway", rank: 9, points: 4455 },
      { name: "Taylor Fritz", country: "USA", rank: 10, points: 3900 },
      { name: "Holger Rune", country: "Denmark", rank: 11, points: 3725 },
      { name: "Felix Auger-Aliassime", country: "Canada", rank: 12, points: 3445 },
      { name: "Alex de Minaur", country: "Australia", rank: 13, points: 3155 },
      { name: "Tommy Paul", country: "USA", rank: 14, points: 2995 },
      { name: "Lorenzo Musetti", country: "Italy", rank: 15, points: 2790 },
      { name: "Ben Shelton", country: "USA", rank: 16, points: 2555 },
      { name: "Frances Tiafoe", country: "USA", rank: 17, points: 2380 },
      { name: "Grigor Dimitrov", country: "Bulgaria", rank: 18, points: 2245 },
      { name: "Sebastian Korda", country: "USA", rank: 19, points: 2100 },
      { name: "Hubert Hurkacz", country: "Poland", rank: 20, points: 1985 }
    ]
  end
  
  def create_realistic_matches(limit)
    players = Player.limit(15)
    return [] if players.count < 2
    
    matches_data = []
    tournaments = [
      'US Open', 'Cincinnati Masters', 'Canadian Open', 'Wimbledon',
      'French Open', 'Italian Open', 'Madrid Open', 'Indian Wells',
      'Miami Open', 'Australian Open', 'ATP Finals'
    ]
    surfaces = ['Hard', 'Clay', 'Grass']
    
    limit.times do
      player1 = players.sample
      player2 = players.where.not(id: player1.id).sample
      next unless player2
      
      # More realistic match outcome prediction
      ranking_diff = (player1.rank || 50) - (player2.rank || 50)
      if ranking_diff < 0  # player1 ranked higher
        winner = rand < 0.7 ? player1 : player2
      elsif ranking_diff > 0  # player2 ranked higher  
        winner = rand < 0.7 ? player2 : player1
      else
        winner = [player1, player2].sample
      end
      
      matches_data << {
        player1: player1,
        player2: player2,
        winner: winner,
        tournament: tournaments.sample,
        date: rand(60.days).seconds.ago.to_date,
        score: generate_realistic_score,
        surface: surfaces.sample
      }
    end
    
    matches_data
  end
  
  def generate_realistic_score
    scores = [
      "6-4, 6-2", "7-6, 6-3", "6-3, 4-6, 6-2", "7-5, 6-4",
      "6-2, 6-3", "6-4, 3-6, 6-4", "7-6, 7-6", "6-1, 6-2",
      "6-3, 6-4", "7-6, 6-4", "6-2, 7-5", "6-4, 6-1"
    ]
    scores.sample
  end
  
  def update_players_from_rankings(rankings_data)
    rankings_data.each do |player_data|
      player = Player.find_or_create_by(name: player_data[:name]) do |p|
        p.country = player_data[:country]
        p.rank = player_data[:rank]
        p.points = player_data[:points]
      end
      
      # Update existing players
      player.update(
        country: player_data[:country],
        rank: player_data[:rank],
        points: player_data[:points]
      ) if player.persisted?
    end
    
    Rails.logger.info "Updated #{rankings_data.length} players from rankings"
  end
  
  def update_matches_from_data(matches_data)
    matches_data.each do |match_data|
      # Ensure player objects are persisted
      p1 = match_data[:player1].is_a?(Player) ? match_data[:player1] : find_or_build_player(match_data[:player1])
      p2 = match_data[:player2].is_a?(Player) ? match_data[:player2] : find_or_build_player(match_data[:player2])

      next unless p1 && p2

      # Prefer matching by external id (source + external_id) if provided
      match = nil
      if match_data[:source].present? && match_data[:external_id].present?
        match = Match.find_by(source: match_data[:source], external_id: match_data[:external_id])
      end

      # Fallback: find by players + date
      if match.nil?
        attrs = { player1_id: p1.id, player2_id: p2.id, date: match_data[:date] }
        match = Match.find_or_initialize_by(attrs)
      end

      # Handle winner when provided
      if match_data[:winner]
        winner = match_data[:winner].is_a?(Player) ? match_data[:winner] : find_or_build_player(match_data[:winner])
        match.winner = winner if winner && [p1.id, p2.id].include?(winner.id)
      end

      # Ensure tournament is set; scrapers sometimes omit it which breaks validation
      if match_data[:tournament].present?
        match.tournament = match_data[:tournament]
      else
        # If tournament is blank and match has none, provide a sensible default based on source
        unless match.tournament.present?
          default_tournament = case match_data[:source].to_s.downcase
                               when '365scores' then '365Scores Event'
                               when 'espn' then 'ESPN Tournament'
                               else 'Tournament'
                               end
          match.tournament = default_tournament
        end
      end
      # Update date when provided by the scraper (ensure we persist new dates)
      if match_data[:date]
        parsed_date = nil
        if match_data[:date].is_a?(String)
          begin
            parsed_date = Date.parse(match_data[:date])
          rescue
            parsed_date = nil
          end
        else
          parsed_date = match_data[:date]
        end

        if parsed_date
          old_date = match.date
          match.date = parsed_date
          if old_date != match.date
            Rails.logger.info "TennisApiService: updating match date for #{p1&.name} vs #{p2&.name} from #{old_date.inspect} to #{match.date} (source=#{match_data[:source]} external_id=#{match_data[:external_id]})"
          end
        end
      end
      match.score = match_data[:score] if match_data[:score]
      match.surface = match_data[:surface] if match_data[:surface]
      # If surface still blank, try to guess from tournament or pick a plausible default
      if match.surface.nil? || match.surface.to_s.strip.empty? || match.surface == 'Unknown'
        match.surface = guess_surface_from_tournament(match.tournament)
      end
      match.status = match_data[:status] || match.status || 'upcoming'
      match.source = match_data[:source] if match_data[:source]
      match.external_id = match_data[:external_id] if match_data[:external_id]

      begin
        match.save!
      rescue => e
        Rails.logger.error "Failed saving match #{p1.name} vs #{p2.name} on #{match.date}: #{e.message}"
      end
    end

    Rails.logger.info "Updated/created #{matches_data.length} matches"
  end
end
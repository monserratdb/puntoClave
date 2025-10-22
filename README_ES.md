PuntoClave — Documentación en español
=====================================

Resumen
-------
PuntoClave es una aplicación web en Ruby on Rails que predice el ganador de partidos de tenis profesional. Usa datos obtenidos por scrapers (principalmente ESPN, 365Scores y fuentes alternativas) y un predictor heurístico en `app/models/match_predictor.rb` que combina ranking, historial Head-to-Head, forma reciente y puntos del jugador para estimar probabilidades.

Objetivo
--------
- Proveer una interfaz simple para comparar dos jugadores y obtener probabilidades de victoria.
- Mantener una base de datos local con jugadores y partidos para alimentar predicciones y mostrar historial.
- Permitir generar y persistir predicciones para futuros partidos entre dos jugadores.

Estructura general del proyecto
-------------------------------
- app/
  - controllers/
    - `predictions_controller.rb`: flujo principal de predicción, vistas y endpoints JSON.
    - `home_controller.rb`: página principal y vistas.
  - models/
    - `player.rb`: representación de jugadores (rank, points, country, etc.).
    - `match.rb`: partidos almacenados (player1, player2, winner, date, tournament, surface, source).
    - `prediction.rb`: predicciones guardadas (player1, player2, predicted_winner, confidence, prediction_date).
    - `match_predictor.rb`: algoritmo que calcula probabilidades y crea `Prediction`.
  - services/
    - `tennis_api_service.rb`: concentrador de scrapers y normalizador. Implementa wrappers para ESPN, 365Scores, TennisPrediction y fallbacks a datos de ejemplo (sample).
    - `atp_scraper_service.rb`: scraper alternativo/experimental para rankings ATP con fallbacks a datos de ejemplo.
  - views/: plantillas HTML para mostrar jugadores, partidos y resultados.

Rutas y endpoints principales
----------------------------
Las rutas están definidas en `config/routes.rb`. A continuación una lista de las rutas más útiles con ejemplos de uso.

Páginas y formularios
- GET / -> página principal (`home#index`).
- GET /predict -> selector de jugadores y vista de predicción (`predictions#index`).
- GET /players -> listado de jugadores (`predictions#players`).
- GET /matches -> listado de partidos (`predictions#matches`).

API / acciones sobre predicciones
- POST /predictions/predict
  - Parámetros: `player1_id`, `player2_id`.
  - Respuesta JSON: `{ predicted_winner, confidence, player1, player2 }` o redirección a `show` en HTML.

- POST /predictions/preview
  - Parámetros: `player1_id`, `player2_id`.
  - Devuelve una predicción no persistida (probabilidades por jugador y confianza).

- GET /predictions/recent
  - Devuelve las predicciones recientes (JSON), usado por refresco automático.

- GET /predictions/:id (show)
  - Muestra una predicción persistida y sus probabilidades.

- POST /predictions/generate_predictions
  - Parámetros: `player1_id`, `player2_id`.
  - Usa `TennisApiService.fetch_upcoming_matches` para obtener próximos enfrentamientos reales y persiste predicciones para cada uno.

- GET /predictions/:id/future_matches
  - Parámetros: `player2_id` (cuando el :id corresponde a player1), `only_next` opcional.
  - Busca fixtures persistidos en DB entre ambos jugadores o usa `TennisApiService.fetch_upcoming_matches` y devuelve probabilidades por fixture.

- POST /predictions/clear_history
  - Borra todas las predicciones. Requiere token ADMIN en entornos de producción (ENV['PUNTOCLAVE_ADMIN_TOKEN']).

- POST /predictions/scrape_data
  - Llama a `TennisApiService` para actualizar rankings y partidos. Usado desde panel admin/rake tasks.

Cómo funciona el predictor (app/models/match_predictor.rb)
---------------------------------------------------------
El predictor actual es heurístico (no es un modelo entrenado) y sigue este flujo:

1. Calcula 4 factores por pareja de jugadores:
   - ranking: inverso de la posición (más alto para mejor ranking).
   - head_to_head: proporción de victorias entre ambos en los encuentros históricos almacenados en `matches`.
   - recent_form: win-rate en últimos 10 partidos de cada jugador (basado en `player.all_matches`).
   - points: proporción relativa de puntos ATP registrados en `player.points`.

2. Normaliza cada factor a una probabilidad relativa para player1 y player2.
3. Combina factores con pesos configurables (por defecto ranking 0.3, head_to_head 0.2, recent_form 0.3, points 0.2).
4. Normaliza la suma de puntuaciones para obtener probabilidades finales; el mayor determina el `predicted_winner`.
5. Si se usa `predict_match_winner`, se persiste un registro `Prediction` con `confidence` = probabilidad del ganador.

Limitaciones actuales
- No hay un modelo ML entrenado; los pesos son fijos y hechos a mano.
- Scrapers pueden fallar por cambios en las webs o por protección anti-scraping. Servicio usa valores sample/fallback cuando falla.
- No hay autenticación avanzada para endpoints admin (solo token env var opcional).

Cómo ejecutar el proyecto localmente
-----------------------------------
Requisitos mínimos:
- Ruby (versión especificada en el Gemfile - usar rbenv/rvm)
- Bundler
- Base de datos configurada en `config/database.yml` (por defecto SQLite o PostgreSQL según ambiente)

Pasos mínimos:

1) Instala dependencias

```bash
bundle install
```

2) Crea y migra la base de datos

```bash
bin/rails db:create db:migrate
```

3) Pobla datos de ejemplo (opcional pero recomendado para desarrollo)

```bash
# Fuerza uso de samples en entornos sin conectividad
export FORCE_SAMPLE=true
# Rellena jugadores de ejemplo y partidos simulados
bin/rails db:seed || bundle exec rails runner "TennisApiService.new.fetch_atp_rankings; TennisApiService.new.fetch_recent_matches(30)"
```

4) Ejecuta el servidor

```bash
bundle exec rails server
```

5) Abre `http://localhost:3000` en tu navegador.

Tareas y rake disponibles (uso típico)
-------------------------------------
- `bin/rails db:scrape:initial` — Scrape inicial para poblar `players` y `matches` (usa `TennisApiService`).
- `bin/rails scrape:daemon` — Daemon ligero para sincronizar periódicamente (desarrollo).

Variables de entorno útiles
--------------------------
- FORCE_SAMPLE=true — evita requests remotos y usa datos de ejemplo.
- PUNTOCLAVE_ADMIN_TOKEN — token para operaciones sensibles (clear_history) en producción.
- SCRAPER_USER_AGENT — user agent para scrapers.

Ejemplos de uso (curl)
----------------------
1) Obtener una predicción y respuesta JSON (preview, no persistida):

```bash
curl -X POST "http://localhost:3000/predictions/preview" \
  -d "player1_id=1&player2_id=2"
```

Respuesta (ejemplo):

```json
{
  "player1": "Novak Djokovic",
  "player2": "Carlos Alcaraz",
  "player1_probability": 62.4,
  "player2_probability": 37.6,
  "predicted_winner": "Novak Djokovic",
  "confidence": 62.4
}
```

2) Guardar una predicción persistida (predict)

```bash
curl -X POST "http://localhost:3000/predictions/predict" \
  -d "player1_id=1&player2_id=2"
```

3) Listar coincidencias recientes entre dos jugadores (JSON):

```bash
curl "http://localhost:3000/predictions/recent_matches?player1_id=1&player2_id=2"
```

Panel de administración (básico)
--------------------------------
- GET /predictions/admin — vista de administración mínima (scraping / limpieza).
- POST /predictions/scrape_data — ejecuta scrapers desde la app.
- POST /predictions/clear_history — borra las predicciones (requiere token en producción).

Buenas prácticas y recomendaciones
---------------------------------
- Proteger endpoints sensibles con autenticación o token en headers.
- Convertir el predictor heurístico en un modelo ML real:
  - Extraer features por partido histórico y generar dataset.
  - Entrenar un modelo (Logistic Regression, XGBoost) y guardarlo (pickle, ONNX o export Ruby-friendly).
  - Sustituir la lógica heurística por inferencia desde el modelo entrenado.
- Añadir pruebas automatizadas para `MatchPredictor` y para `TennisApiService` (usar VCR o WebMock para simular respuestas remotas).
- Usar Sidekiq/ActiveJob para tareas de scraping en background.
- Añadir límites/ratelimit para scrapers y respetar robots.txt y políticas de los proveedores de datos.

Próximos pasos sugeridos (priorizados)
--------------------------------------
1. Tests unitarios para `MatchPredictor` con casos determinísticos y fixtures de partidos.
2. Pipeline de features + entrenamiento (Python/Scikit-Learn o Ruby + XGBoost) para convertir heurística en modelo.
3. Endpoint /admin seguro con autenticación básica y logs de scraping.
4. Automatizar la creación de fixtures reales con una integración robusta (API con key o scraping con Selenium si es imprescindible).

Contacto y mantenimiento
------------------------
- Este repositorio pertenece a la cuenta local del desarrollador. Para problemas con scrapers, revisa los logs en `log/` y activa `FORCE_SAMPLE=true` para desarrollo.

Resumen de cambios en el proyecto
--------------------------------
- El proyecto ya incluye un predictor heurístico en `app/models/match_predictor.rb`.
- `TennisApiService` y `AtpScraperService` ofrecen scrapers y data fallbacks.
- `PredictionsController` expone endpoints para previsualizar, predecir y generar predicciones persistidas.

Licencia y uso
---------------
Uso personal/educativo. No afiliado a ATP ni a proveedores de datos oficiales.


-- Fin de documentación --

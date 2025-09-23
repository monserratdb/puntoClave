# README - PuntoClave

PuntoClave es una aplicación web en Ruby on Rails que utiliza inteligencia artificial para predecir el ganador de partidos de tenis profesional ATP. Permite comparar dos jugadores y ver quién tiene más probabilidades de ganar, además de consultar futuros enfrentamientos entre ellos.

## Características principales
- Predicción de partidos ATP usando IA y estadísticas reales
- Selección de jugadores y visualización de probabilidades de victoria
- Consulta de futuros partidos entre dos jugadores
- Páginas dedicadas para jugadores y partidos
- Interfaz completamente en español

## ¿Cómo funciona?
PuntoClave utiliza un algoritmo de machine learning que combina:
- **Ranking ATP y puntos oficiales**
- **Historial de enfrentamientos directos (H2H)**
- **Forma reciente (últimos 10 partidos)**
- **Estadísticas de partidos y jugadores**

La IA asigna pesos a cada factor y calcula la probabilidad de victoria para cada jugador. Los datos se obtienen de la web oficial ATP o mediante scraping automatizado (Selenium).

## Instalación y uso

### 1. Instala dependencias
```bash
bundle install
```

### 2. Configura la base de datos
```bash
bundle exec rails db:migrate
```

### 3. Carga datos de jugadores y partidos
Puedes usar scraping básico o Selenium para obtener datos reales. Por defecto, se cargan datos de ejemplo.
```bash
bundle exec rails console
AtpScraperService.new.scrape_rankings
AtpScraperService.new.scrape_recent_matches(30)
exit
```

### 4. Inicia el servidor
```bash
bundle exec rails server
```

### 5. Abre la aplicación
Accede a [http://localhost:3000](http://localhost:3000) en tu navegador.

## Scraping avanzado (opcional)
Para obtener datos reales y actualizados, puedes usar Selenium:
- Instala Chrome y Chromedriver
- Agrega los gems `selenium-webdriver` y `webdrivers` al Gemfile
- Usa el servicio `SeleniumAtpScraper` para poblar la base de datos

## Estructura del proyecto
- `app/models/match_predictor.rb`: Algoritmo de predicción IA
- `app/services/atp_scraper_service.rb`: Scraping básico ATP
- `app/services/selenium_atp_scraper.rb`: Scraping avanzado con Selenium
- `app/controllers/predictions_controller.rb`: Lógica principal de predicción
- `app/views/`: Vistas y páginas de la aplicación

## Créditos y licencia
Este proyecto es solo para fines educativos y personales. No está afiliado a la ATP ni a los proveedores de datos oficiales.

---

**¡Disfruta PuntoClave y predice el tenis como un profesional!**

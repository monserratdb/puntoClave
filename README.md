# README - PuntoClave

PuntoClave es una aplicación web en Ruby on Rails que utiliza inteligencia artificial para predecir el ganador de partidos de tenis profesional. Permite comparar dos jugadores y ver quién tiene más probabilidades de ganar, además de consultar futuros enfrentamientos entre ellos.

## Características principales
- Predicción de partidos ATP usando IA y estadísticas reales
- Selección de jugadores y visualización de probabilidades de victoria
- Consulta de futuros partidos entre dos jugadores
- Páginas dedicadas para jugadores y partidos
- Interfaz completamente en español

## ¿Cómo funciona?
PuntoClave utiliza un algoritmo de machine learning que combina:
- **Ranking y puntos oficiales (obtenidos vía scraping de fuentes públicas como ESPN)**
- **Historial de enfrentamientos directos (H2H)**
- **Forma reciente (últimos 10 partidos)**
- **Estadísticas de partidos y jugadores**

La IA asigna pesos a cada factor y calcula la probabilidad de victoria para cada jugador. Los datos se obtienen principalmente de ESPN mediante scraping (HTTP + Nokogiri). Hemos removido la dependencia de la página oficial de la ATP por bloqueos y fiabilidad.

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
Por simplicidad y fiabilidad usamos ESPN como fuente primaria. Por defecto, se cargan datos de ejemplo si las llamadas remotas fallan.

Opciones para poblar la base de datos con datos (elige una):

- Usar la tarea Rake (recomendada para inicializar desde cero):

```bash
# Crear DB y migrar (si no lo hiciste aun)
bin/rails db:create db:migrate

# Ejecutar scraping que poblará jugadores y partidos (usa ESPN)
bin/rails db:scrape:initial
```

- O usar la consola Rails (método manual, equivalente):

```bash
bundle exec rails console
TennisApiService.new.fetch_atp_rankings
TennisApiService.new.fetch_recent_matches(30)
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

## Scraping daemon (refresh ESPN players and 365Scores matches)

Puedes ejecutar un daemon ligero que actualizará jugadores (desde ESPN) y obtendrá partidos recientes/próximos (preferentemente desde 365Scores) cada N minutos mientras el proceso esté activo.

Ejemplo (intervalo por defecto 30 minutos):

```bash
# desde la raíz del proyecto
bundle exec rails scrape:daemon
```

Configurar intervalo y reemplazo destructivo:

```bash
# ejecutar cada 15 minutos
SCRAPE_INTERVAL_MINUTES=15 bundle exec rails scrape:daemon

# reemplazar de forma destructiva la tabla de jugadores desde ESPN (usar con precaución)
FORCE_REPLACE=true bundle exec rails scrape:daemon
```

Notas:
- Esta tarea rake está pensada para entornos de desarrollo o despliegues simples donde puedas lanzar manualmente el proceso mientras la app está activa. Para producción, es preferible usar un scheduler (cron, systemd timer) o Sidekiq con jobs periódicos.
- El daemon usa `TennisApiService` (ESPN y 365Scores) y actualiza la base de datos con datos de scraping.

## Estructura del proyecto
- `app/models/match_predictor.rb`: Algoritmo de predicción IA
-- `app/services/tennis_api_service.rb`: Scraping y wrappers para ESPN, 365Scores y TennisPrediction (principalmente ESPN ahora)
- `app/controllers/predictions_controller.rb`: Lógica principal de predicción
- `app/views/`: Vistas y páginas de la aplicación

## Créditos y licencia
Este proyecto es solo para fines educativos y personales. No está afiliado a la ATP ni a los proveedores de datos oficiales.

---

**¡Disfruta PuntoClave y predice el tenis como un profesional!**

# Weather 

A Flutter application that displays real-time weather data across multiple cities, built on the OpenWeatherMap API.

---

## Overview

Weather Dashboard presents live conditions for a configurable set of cities in a responsive card grid. Each card surfaces temperature, description, humidity, wind speed, and daily min/max. Cities can be added or removed at runtime without restarting the app.

---

## Architecture

The app uses a lightweight layered architecture with no external state management packages.

```
UI (Widgets)
    └── WeatherController (ChangeNotifier)
            └── WeatherRepository
                    └── OpenWeatherMap API
```

- **WeatherData** — immutable model with a `fromJson` factory
- **WeatherRepository** — owns all HTTP logic via `dart:io`'s `HttpClient`
- **WeatherController** — holds `WeatherState` and exposes `loadAll()`, `addCity()`, and `removeCity()`
- **Widgets** — listen via `addListener` / `setState`; no third-party state library required

---

## Dependencies

| Package | Version | Purpose |
|---|---|---|
| `flutter_dotenv` | `^5.1.0` | Reads `OPENWEATHER_API_KEY` from `.env` |
| `http` | `^1.2.0` | HTTP client for API requests |
| `cupertino_icons` | `^1.0.8` | iOS-style icon set |

---

## Configuration

The app reads a single environment variable:

| Variable | Description |
|---|---|
| `OPENWEATHER_API_KEY` | OpenWeatherMap API key |

The `.env` file is declared as a Flutter asset and loaded at startup via `flutter_dotenv`.

Default cities are defined in `AppConstants.defaultCities` and can be adjusted without touching any other file.

---

## Requirements

- Flutter `^3.11.1`
- Dart `^3.11.1`
- OpenWeatherMap API key (free tier supported)
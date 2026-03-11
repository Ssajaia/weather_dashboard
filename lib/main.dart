import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

// ─── Entry Point ────────────────────────────────────────────────────────────

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  runApp(const WeatherApp());
}

// ─── App Root ────────────────────────────────────────────────────────────────

class WeatherApp extends StatelessWidget {
  const WeatherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Weather',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const WeatherDashboardScreen(),
    );
  }
}

// ─── Constants ───────────────────────────────────────────────────────────────

class AppConstants {
  AppConstants._();

  static const String baseUrl = 'https://api.openweathermap.org/data/2.5';
  static const String iconBaseUrl = 'https://openweathermap.org/img/wn';
  static const String units = 'metric';
  static const String lang = 'en';

  static const List<String> defaultCities = [
    'chkorotsku',
    'New York',
    'Tokyo',
    'Paris',
    'Sydney',
    'Dubai',
  ];
}

// ─── Models ──────────────────────────────────────────────────────────────────

class WeatherData {
  const WeatherData({
    required this.cityName,
    required this.country,
    required this.temperature,
    required this.feelsLike,
    required this.humidity,
    required this.windSpeed,
    required this.description,
    required this.iconCode,
    required this.tempMin,
    required this.tempMax,
  });

  final String cityName;
  final String country;
  final double temperature;
  final double feelsLike;
  final int humidity;
  final double windSpeed;
  final String description;
  final String iconCode;
  final double tempMin;
  final double tempMax;

  String get iconUrl => '${AppConstants.iconBaseUrl}/$iconCode@2x.png';

  factory WeatherData.fromJson(Map<String, dynamic> json) {
    final main = json['main'] as Map<String, dynamic>;
    final weather = (json['weather'] as List).first as Map<String, dynamic>;
    final wind = json['wind'] as Map<String, dynamic>;
    final sys = json['sys'] as Map<String, dynamic>;

    return WeatherData(
      cityName: json['name'] as String,
      country: sys['country'] as String,
      temperature: (main['temp'] as num).toDouble(),
      feelsLike: (main['feels_like'] as num).toDouble(),
      humidity: main['humidity'] as int,
      windSpeed: (wind['speed'] as num).toDouble(),
      description: weather['description'] as String,
      iconCode: weather['icon'] as String,
      tempMin: (main['temp_min'] as num).toDouble(),
      tempMax: (main['temp_max'] as num).toDouble(),
    );
  }
}

// ─── Repository ──────────────────────────────────────────────────────────────

class WeatherRepository {
  WeatherRepository({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  final String _apiKey = dotenv.env['OPENWEATHER_API_KEY'];
    
    
  }

  Future<WeatherData> fetchWeather(String city) async {
    final uri = Uri.parse(
      '${AppConstants.baseUrl}/weather'
      '?q=${Uri.encodeComponent(city)}'
      '&units=${AppConstants.units}'
      '&lang=${AppConstants.lang}'
      '&appid=$_apiKey',
    );

    final response = await _client.get(uri);

    if (response.statusCode == 200) {
      return WeatherData.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } else if (response.statusCode == 404) {
      throw Exception('City "$city" not found.');
    } else if (response.statusCode == 401) {
      throw Exception('Invalid API key. Check your OPENWEATHER_API_KEY.');
    } else {
      throw Exception('Failed to fetch weather (HTTP ${response.statusCode}).');
    }
  }

  Future<List<WeatherData>> fetchMultiple(List<String> cities) async {
    final results = await Future.wait(
      cities.map((city) => fetchWeather(city)),
      eagerError: false,
    );
    return results;
  }
}

// ─── State ───────────────────────────────────────────────────────────────────

enum LoadingStatus { idle, loading, success, failure }

class WeatherState {
  const WeatherState({
    this.status = LoadingStatus.idle,
    this.weatherList = const [],
    this.errorMessage,
  });

  final LoadingStatus status;
  final List<WeatherData> weatherList;
  final String? errorMessage;

  WeatherState copyWith({
    LoadingStatus? status,
    List<WeatherData>? weatherList,
    String? errorMessage,
    bool clearError = false,
  }) {
    return WeatherState(
      status: status ?? this.status,
      weatherList: weatherList ?? this.weatherList,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

// ─── Controller / ViewModel ──────────────────────────────────────────────────

class WeatherController extends ChangeNotifier {
  WeatherController({WeatherRepository? repository})
    : _repository = repository ?? WeatherRepository();

  final WeatherRepository _repository;

  WeatherState _state = const WeatherState();
  WeatherState get state => _state;

  final List<String> _cities = List.from(AppConstants.defaultCities);
  List<String> get cities => List.unmodifiable(_cities);

  Future<void> loadAll() async {
    _state = _state.copyWith(status: LoadingStatus.loading);
    notifyListeners();

    final results = <WeatherData>[];
    String? lastError;

    for (final city in _cities) {
      try {
        final data = await _repository.fetchWeather(city);
        results.add(data);
      } catch (e) {
        lastError = e.toString().replaceFirst('Exception: ', '');
      }
    }

    _state = _state.copyWith(
      status: results.isEmpty ? LoadingStatus.failure : LoadingStatus.success,
      weatherList: results,
      errorMessage: lastError,
    );
    notifyListeners();
  }

  Future<void> addCity(String city) async {
    final normalised = city.trim();
    if (normalised.isEmpty) return;

    try {
      final data = await _repository.fetchWeather(normalised);

      // Guard against duplicate using the API-returned name
      final alreadyExists = _state.weatherList.any(
        (w) => w.cityName.toLowerCase() == data.cityName.toLowerCase(),
      );
      if (alreadyExists) return;

      _cities.add(data.cityName);
      _state = _state.copyWith(
        status: LoadingStatus.success,
        weatherList: [..._state.weatherList, data],
        clearError: true,
      );
    } catch (e) {
      _state = _state.copyWith(
        errorMessage: e.toString().replaceFirst('Exception: ', ''),
      );
    }
    notifyListeners();
  }

  void removeCity(String cityName) {
    // Remove from both lists using the API cityName as the key
    _cities.removeWhere((c) => c.toLowerCase() == cityName.toLowerCase());
    _state = _state.copyWith(
      weatherList: _state.weatherList
          .where((w) => w.cityName != cityName)
          .toList(),
      clearError: true,
    );
    notifyListeners();
  }
}

// ─── Screen ──────────────────────────────────────────────────────────────────

class WeatherDashboardScreen extends StatefulWidget {
  const WeatherDashboardScreen({super.key});

  @override
  State<WeatherDashboardScreen> createState() => _WeatherDashboardScreenState();
}

class _WeatherDashboardScreenState extends State<WeatherDashboardScreen> {
  late final WeatherController _controller;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = WeatherController();
    _controller.addListener(() => setState(() {}));
    _controller.loadAll();
  }

  @override
  void dispose() {
    _controller.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ── Handlers ──────────────────────────────────────────────────────────────

  Future<void> _onAddCity() async {
    final city = _searchController.text.trim();
    if (city.isEmpty) return;
    _searchController.clear();
    await _controller.addCity(city);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      appBar: _buildAppBar(),
      body: _buildBody(),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      title: const Text(
        'Weather Dashboard',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 22,
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh, color: Colors.white70),
          tooltip: 'Refresh all',
          onPressed: _controller.loadAll,
        ),
      ],
    );
  }

  Widget _buildBody() {
    final state = _controller.state;

    return Column(
      children: [
        _SearchBar(
          controller: _searchController,
          onSubmitted: (_) => _onAddCity(),
          onAdd: _onAddCity,
        ),
        if (state.errorMessage != null)
          _ErrorBanner(message: state.errorMessage!),
        Expanded(
          child: switch (state.status) {
            LoadingStatus.idle || LoadingStatus.loading =>
              state.weatherList.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _WeatherGrid(
                      items: state.weatherList,
                      onRemove: _controller.removeCity,
                    ),
            LoadingStatus.failure => _EmptyState(onRetry: _controller.loadAll),
            LoadingStatus.success => _WeatherGrid(
              items: state.weatherList,
              onRemove: _controller.removeCity,
            ),
          },
        ),
      ],
    );
  }
}

// ─── Widgets ─────────────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.onSubmitted,
    required this.onAdd,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              onSubmitted: onSubmitted,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Add a city…',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search, color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF1E2D3D),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: onAdd,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1565C0),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade900.withOpacity(0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.shade700),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeatherGrid extends StatelessWidget {
  const _WeatherGrid({required this.items, required this.onRemove});

  final List<WeatherData> items;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = (constraints.maxWidth / 300).floor().clamp(1, 4);
        final cardWidth =
            (constraints.maxWidth - 16 * (crossAxisCount - 1)) / crossAxisCount;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Wrap(
            spacing: 16,
            runSpacing: 16,
            children: items
                .map(
                  (w) => SizedBox(
                    width: cardWidth,
                    child: _WeatherCard(
                      data: w,
                      onRemove: () => onRemove(w.cityName),
                    ),
                  ),
                )
                .toList(),
          ),
        );
      },
    );
  }
}

class _WeatherCard extends StatelessWidget {
  const _WeatherCard({required this.data, required this.onRemove});

  final WeatherData data;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E3A5F), Color(0xFF0D1B2A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // City + icon row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            data.cityName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                          Text(
                            data.country,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Image.network(
                      data.iconUrl,
                      width: 44,
                      height: 44,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.cloud,
                        color: Colors.white54,
                        size: 36,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 4),

                // Temperature
                Text(
                  '${data.temperature.round()}°C',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w300,
                    height: 1.1,
                  ),
                ),

                Text(
                  _capitalise(data.description),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),

                const SizedBox(height: 10),

                // Details row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _Detail(
                      icon: Icons.water_drop_outlined,
                      label: '${data.humidity}%',
                    ),
                    _Detail(
                      icon: Icons.air,
                      label: '${data.windSpeed.toStringAsFixed(1)} m/s',
                    ),
                    _Detail(
                      icon: Icons.thermostat_outlined,
                      label:
                          '${data.tempMin.round()}°/${data.tempMax.round()}°',
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Remove button
          Positioned(
            top: 2,
            right: 2,
            child: IconButton(
              icon: const Icon(Icons.close, size: 14, color: Colors.white38),
              onPressed: onRemove,
              tooltip: 'Remove',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
          ),
        ],
      ),
    );
  }

  String _capitalise(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class _Detail extends StatelessWidget {
  const _Detail({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.white54, size: 14),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off, color: Colors.white38, size: 64),
          const SizedBox(height: 16),
          const Text(
            'Could not load weather data.',
            style: TextStyle(color: Colors.white54, fontSize: 16),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

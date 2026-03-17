import 'dart:convert';
import 'package:http/http.dart' as http;

class TMDBService {
  static const String apiKey = '97293f46c7a2e36b511c6109f64f18ae';
  static const String baseUrl = 'https://api.themoviedb.org/3';

  Future<List<dynamic>> fetchCurrentMonthMovies(DateTime currentDate) async {
    final year = currentDate.year;
    final month = currentDate.month.toString().padLeft(2, '0');

    final lastDay = DateTime(
      year,
      currentDate.month + 1,
      0,
    ).day.toString().padLeft(2, '0');

    final startStr = '$year-$month-01';
    final endStr = '$year-$month-$lastDay';

    final url = Uri.parse(
      '$baseUrl/discover/movie?api_key=$apiKey&language=en-US&region=US&sort_by=popularity.desc&release_date.gte=$startStr&release_date.lte=$endStr&with_release_type=3',
    );

    try {
      List<dynamic> allResults = [];

      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        allResults.addAll(data['results'] ?? []);

        int totalPages = data['total_pages'] ?? 1;
        int maxPages = totalPages > 4 ? 4 : totalPages;

        if (maxPages > 1) {
          List<Future<http.Response>> futures = [];
          for (int p = 2; p <= maxPages; p++) {
            futures.add(http.get(Uri.parse(url.toString() + '&page=$p')));
          }
          final responses = await Future.wait(futures);
          for (var res in responses) {
            if (res.statusCode == 200) {
              allResults.addAll(json.decode(res.body)['results'] ?? []);
            }
          }
        }

        final targetPrefix = '$year-$month';
        allResults = allResults.where((m) {
          final rDate = m['release_date'];
          if (m['poster_path'] == null || rDate == null || rDate.isEmpty)
            return false;
          return rDate.startsWith(targetPrefix);
        }).toList();

        allResults.sort(
          (a, b) => a['release_date'].compareTo(b['release_date']),
        );

        return allResults;
      } else {
        print('Server error: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('Network error: $e');
      return [];
    }
  }

  Future<List<dynamic>> searchMovies(String query) async {
    if (query.isEmpty) return [];

    final url = Uri.parse(
      '$baseUrl/search/movie?api_key=$apiKey&language=en-US&query=${Uri.encodeComponent(query)}&page=1&include_adult=false',
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        List<dynamic> results = data['results'] ?? [];

        results = results.where((m) => m['poster_path'] != null).toList();
        return results;
      } else {
        print('Server error searching: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('Network error searching: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> fetchMovieDetails(int movieId) async {
    final url = Uri.parse(
      '$baseUrl/movie/$movieId?api_key=$apiKey&append_to_response=credits',
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        print('Server error fetching details: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Network error: $e');
      return null;
    }
  }

  // --- ADDED RUNTIME METHOD ---
  Future<int> getMovieRuntime(int movieId) async {
    final url = Uri.parse('$baseUrl/movie/$movieId?api_key=$apiKey&language=en-US');

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final int runtime = data['runtime'] ?? 0;
        return runtime > 0 ? runtime : 120;
      } else {
        print('Server error fetching runtime: ${response.statusCode}');
        return 120;
      }
    } catch (e) {
      print('Network error fetching runtime: $e');
      return 120;
    }
  }
}
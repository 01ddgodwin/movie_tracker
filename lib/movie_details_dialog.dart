import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'tmdb_service.dart';
import 'save_ticket_dialog.dart';
import 'add_plan_dialog.dart';

class MovieDetailsDialog extends StatefulWidget {
  final int movieId;

  const MovieDetailsDialog({super.key, required this.movieId});

  @override
  State<MovieDetailsDialog> createState() => _MovieDetailsDialogState();
}

class _MovieDetailsDialogState extends State<MovieDetailsDialog> {
  final TMDBService _tmdbService = TMDBService();
  Map<String, dynamic>? _movieDetails;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    final details = await _tmdbService.fetchMovieDetails(widget.movieId);
    if (mounted) {
      setState(() {
        _movieDetails = details;
        _isLoading = false;
      });
    }
  }

  Future<void> _launchShowtimes(String title) async {
    final query = Uri.encodeComponent('$title movie showtimes near me');
    final url = Uri.parse('https://www.google.com/search?q=$query');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      debugPrint('Could not launch $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      insetPadding: const EdgeInsets.all(16),
      child: _isLoading
          ? const SizedBox(
              height: 200,
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFFE50914)),
              ),
            )
          : _movieDetails == null
              ? const SizedBox(
                  height: 200,
                  child: Center(child: Text('Error loading details.', style: TextStyle(color: Colors.white))),
                )
              : _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final posterPath = _movieDetails!['poster_path'];
    final imageUrl = posterPath != null
        ? 'https://image.tmdb.org/t/p/w200$posterPath'
        : '';
    final title = _movieDetails!['title'] ?? 'Unknown';
    final releaseDate = _movieDetails!['release_date'] ?? 'TBD';
    final year = releaseDate.isNotEmpty ? releaseDate.substring(0, 4) : 'TBD';
    final rating = _movieDetails!['vote_average']?.toStringAsFixed(1) ?? 'NR';

    final genresList = _movieDetails!['genres'] as List<dynamic>? ?? [];
    final genres = genresList.map((g) => g['name']).join(', ');

    final castList = _movieDetails!['credits']?['cast'] as List<dynamic>? ?? [];
    final cast = castList.take(5).map((c) => c['name']).join(', ');

    final overview = _movieDetails!['overview'] ?? 'No overview available.';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Close button
          Align(
            alignment: Alignment.topRight,
            child: InkWell(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Color(0xFF333333),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 20, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Header: Poster & Basic Info
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: imageUrl.isNotEmpty
                    ? Image.network(imageUrl, width: 100, fit: BoxFit.cover)
                    : Container(
                        width: 100,
                        height: 150,
                        color: Colors.grey[800],
                      ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF333333),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            year,
                            style: const TextStyle(fontSize: 12, color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF333333),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '★ $rating',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFFf5c518),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      genres,
                      style: const TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Overview & Cast
          const Text(
            'Overview',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            overview,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFFDDDDDD),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),

          const Text(
            'Top Cast',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            cast.isNotEmpty ? cast : 'No cast data.',
            style: const TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 24),

          // Action Buttons
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF007BFF),
              minimumSize: const Size(double.infinity, 50),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => _launchShowtimes(title),
            icon: const Text('🎟️'),
            label: const Text(
              'Find Local Showtimes',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFF555555)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () async {
                    Navigator.pop(context); // Close details
                    final result = await showDialog(
                      context: context,
                      builder: (context) => SaveTicketDialog(movie: _movieDetails!),
                    );
                    if (result == true && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Ticket saved! 🎟️'), backgroundColor: Colors.green),
                      );
                    }
                  },
                  icon: const Text('📱'),
                  label: const Text(
                    'Save Ticket',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFF555555)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () async {
                    Navigator.pop(context); // Close details
                    await showDialog(
                      context: context,
                      builder: (context) => const AddPlanDialog(),
                    );
                  },
                  icon: const Text('🍿'),
                  label: const Text(
                    'Plan with Friends',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
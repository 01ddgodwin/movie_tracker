import 'package:flutter/material.dart';
import 'storage_service.dart';
import 'firebase_service.dart';

class DiaryScreen extends StatefulWidget {
  const DiaryScreen({Key? key}) : super(key: key);

  @override
  State<DiaryScreen> createState() => _DiaryScreenState();
}

class _DiaryScreenState extends State<DiaryScreen> {
  final StorageService _storageService = StorageService();
  final FirebaseService _firebaseService = FirebaseService();
  List<dynamic> _diaryEntries = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDiary();
  }

  Future<void> _loadDiary() async {
    final list = await _storageService.getDiary();
    if (mounted) {
      setState(() {
        _diaryEntries = list;
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteEntry(String id) async {
    await _storageService.removeFromDiary(id);
    await _loadDiary(); // Refresh local list

    // Sync deletion to cloud
    if (_firebaseService.currentUser != null) {
      final watchlist = await _storageService.getWatchlist();
      final tickets = await _storageService.getTickets();
      await _firebaseService.syncToCloud(
        watchlist: watchlist,
        diary: _diaryEntries,
        tickets: tickets,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🎬 My Movie Diary'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFE50914)))
          : _diaryEntries.isEmpty
              ? const Center(
                  child: Text('No movies logged yet. Start watching!',
                      style: TextStyle(color: Colors.grey)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _diaryEntries.length,
                  itemBuilder: (context, index) {
                    final entry = _diaryEntries[index];
                    return Card(
                      color: const Color(0xFF1E1E1E),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Poster Thumbnail
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: entry['posterPath'] != null
                                  ? Image.network(
                                      'https://image.tmdb.org/t/p/w200${entry['posterPath']}',
                                      width: 60,
                                      height: 90,
                                      fit: BoxFit.cover,
                                    )
                                  : Container(
                                      width: 60,
                                      height: 90,
                                      color: Colors.grey[800],
                                      child: const Icon(Icons.movie, color: Colors.white24),
                                    ),
                            ),
                            const SizedBox(width: 16),
                            // Entry Details
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    entry['title'] ?? 'Unknown Movie',
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(Icons.star, color: Colors.amber, size: 16),
                                      const SizedBox(width: 4),
                                      Text('${entry['rating']}/10',
                                          style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
                                      const Spacer(),
                                      Text(entry['dateWatched'] ?? '',
                                          style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  if (entry['review'] != null && entry['review'].isNotEmpty)
                                    Text(
                                      '"${entry['review']}"',
                                      style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.white70),
                                    ),
                                ],
                              ),
                            ),
                            // Delete Button
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.grey, size: 20),
                              onPressed: () => _deleteEntry(entry['id'].toString()),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
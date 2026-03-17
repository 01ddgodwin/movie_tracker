import 'package:flutter/material.dart';
import 'firebase_service.dart';

class FriendProfileDialog extends StatefulWidget {
  final Map<String, dynamic> friend;

  const FriendProfileDialog({super.key, required this.friend});

  @override
  State<FriendProfileDialog> createState() => _FriendProfileDialogState();
}

class _FriendProfileDialogState extends State<FriendProfileDialog> {
  final FirebaseService _firebaseService = FirebaseService();
  late Future<List<Map<String, dynamic>>> _diaryFuture;

  @override
  void initState() {
    super.initState();
    _diaryFuture = _firebaseService.fetchFriendDiary(widget.friend['uid']);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24), // Makes it fit the screen nicely
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // --- HEADER ---
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color(0xFF111111),
                border: Border(bottom: BorderSide(color: Color(0xFF333333))),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: const Color(0xFF444444),
                    backgroundImage: widget.friend['photoURL'] != null && widget.friend['photoURL'].toString().isNotEmpty
                        ? NetworkImage(widget.friend['photoURL'])
                        : null,
                    child: widget.friend['photoURL'] == null || widget.friend['photoURL'].toString().isEmpty
                        ? const Text('🎬', style: TextStyle(fontSize: 24))
                        : null,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.friend['displayName'] ?? 'Friend', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        const Text('🎬 Movie Diary', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey),
                    onPressed: () => Navigator.pop(context),
                  )
                ],
              ),
            ),

            // --- BODY ---
            Flexible(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _diaryFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator(color: Color(0xFFE50914))));
                  }

                  final diary = snapshot.data ?? [];
                  final rated = diary.where((m) => (m['rating'] ?? 0) > 0).toList();
                  final avg = rated.isNotEmpty ? rated.fold(0.0, (s, m) => s + (m['rating'] ?? 0)) / rated.length : 0.0;
                  
                  // Find the top-rated movie
                  Map<String, dynamic>? topRated;
                  if (rated.isNotEmpty) {
                    topRated = rated.reduce((curr, next) => (curr['rating'] ?? 0) > (next['rating'] ?? 0) ? curr : next);
                  }

                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // --- RECAP STATS ---
                        const Text('ALL-TIME RECAP', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(colors: [Color(0xFFE040FB), Color(0xFF7C4DFF)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                                  borderRadius: BorderRadius.circular(12)
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('LOGGED', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 4),
                                    Text('${diary.length}', style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold, height: 1.1)),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(colors: [Color(0xFFFFB74D), Color(0xFFF57C00)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                                  borderRadius: BorderRadius.circular(12)
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('AVG ★', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 4),
                                    Text(avg.toStringAsFixed(1), style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold, height: 1.1)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),

                        // --- TOP RATED SECTION ---
                        if (topRated != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [Color(0xFF651FFF), Color(0xFF311B92)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                              borderRadius: BorderRadius.circular(12)
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('TOP RATED', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: Image.network(
                                        topRated['posterPath'] != null && topRated['posterPath'].toString().isNotEmpty
                                          ? 'https://image.tmdb.org/t/p/w200${topRated['posterPath']}'
                                          : '',
                                        width: 50,
                                        height: 75,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Container(width: 50, height: 75, color: Colors.black45),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(topRated['title'] ?? 'Unknown', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              const Icon(Icons.star, color: Color(0xFFf5c518), size: 16),
                                              const SizedBox(width: 4),
                                              Text(topRated['rating'].toStringAsFixed(1), style: const TextStyle(color: Color(0xFFf5c518), fontSize: 14, fontWeight: FontWeight.bold)),
                                            ],
                                          )
                                        ],
                                      ),
                                    )
                                  ],
                                )
                              ],
                            ),
                          )
                        ],

                        const SizedBox(height: 24),
                        const Text('ALL-TIME DIARY', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
                        const Divider(color: Color(0xFF333333), height: 24),
                        
                        if (diary.isEmpty)
                          const Padding(padding: EdgeInsets.all(16), child: Center(child: Text('No movies logged yet.', style: TextStyle(color: Colors.grey)))),
                        
                        if (diary.isNotEmpty)
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              childAspectRatio: 0.48, // Taller ratio for title & stars
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 16,
                            ),
                            itemCount: diary.length,
                            itemBuilder: (context, i) {
                              final m = diary[i];
                              final poster = m['posterPath'];
                              final img = poster != null && poster != 'null' ? 'https://image.tmdb.org/t/p/w200$poster' : '';
                              final r = m['rating']?.toString() ?? '0.0';
                              final dRating = r.contains('.') ? r : '$r.0';
                              
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: img.isNotEmpty 
                                        ? Image.network(img, fit: BoxFit.cover, errorBuilder: (_,__,___) => Container(color: Colors.grey[800])) 
                                        : Container(color: Colors.grey[800]),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(m['title'] ?? 'Unknown', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                                  const SizedBox(height: 2),
                                  Text('★ $dRating', style: const TextStyle(color: Color(0xFFf5c518), fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                                ],
                              );
                            },
                          )
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'firebase_service.dart';
import 'amc_stubs_card.dart';

class ProfileTab extends StatefulWidget {
  final List<dynamic> diary;
  final List<dynamic> watchlist;
  final VoidCallback onSignOut;

  const ProfileTab({
    super.key, 
    required this.diary, 
    required this.watchlist, 
    required this.onSignOut
  });

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  final FirebaseService _firebaseService = FirebaseService();
  final ScreenshotController _screenshotController = ScreenshotController();
  
  String _selectedYear = DateTime.now().year.toString();
  List<String> _availableYears = [];
  bool _isSharing = false;

  @override
  void initState() {
    super.initState();
    _extractYears();
  }

  @override
  void didUpdateWidget(covariant ProfileTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.diary != oldWidget.diary) _extractYears();
  }

  void _extractYears() {
    final Set<String> years = {DateTime.now().year.toString()};
    for (var movie in widget.diary) {
      if (movie['watchedDate'] != null) {
        try {
          final date = DateTime.parse(movie['watchedDate']);
          years.add(date.year.toString());
        } catch (_) {}
      }
    }
    _availableYears = years.toList()..sort((a, b) => b.compareTo(a));
  }

  // --- SHARE RECAP LOGIC ---
  Future<void> _shareRecap() async {
    setState(() => _isSharing = true);
    try {
      final image = await _screenshotController.capture(
        pixelRatio: 3.0, 
        delay: const Duration(milliseconds: 100)
      );

      if (image != null) {
        final directory = await getTemporaryDirectory();
        final imagePath = File('${directory.path}/movie_recap_$_selectedYear.png');
        await imagePath.writeAsBytes(image);

        await Share.shareXFiles(
          [XFile(imagePath.path)], 
          text: 'My $_selectedYear Movie Recap! 🍿 #MyMovieCalendar'
        );
      }
    } catch (e) {
      debugPrint('Share error: $e');
    } finally {
      setState(() => _isSharing = false);
    }
  }

  Widget _buildMemoryImage(String path) {
    if (path.startsWith('data:image')) {
      try {
        final base64Str = path.split(',').last;
        return Image.memory(base64Decode(base64Str), fit: BoxFit.cover);
      } catch (_) { return Container(color: Colors.black); }
    }
    return Image.file(File(path), fit: BoxFit.cover, errorBuilder: (c, e, s) => Container(color: Colors.black));
  }

  @override
  Widget build(BuildContext context) {
    final user = _firebaseService.currentUser;
    if (user == null) return const Center(child: Text('Sign in to view profile.'));

    final yearDiary = widget.diary.where((m) => m['watchedDate']?.toString().startsWith(_selectedYear) ?? false).toList();
    final ratedMovies = yearDiary.where((m) => (m['rating'] ?? 0) > 0).toList();
    final double avgRating = ratedMovies.isNotEmpty 
        ? ratedMovies.fold(0.0, (sum, m) => sum + (m['rating'] ?? 0)) / ratedMovies.length 
        : 0.0;
    
    Map<String, dynamic>? topRated;
    if (ratedMovies.isNotEmpty) {
      topRated = ratedMovies.reduce((a, b) => (a['rating'] ?? 0) > (b['rating'] ?? 0) ? a : b);
    }

    Map<int, int> monthCounts = {};
    Map<int, int> dayCounts = {};
    for (var m in yearDiary) {
      final date = DateTime.tryParse(m['watchedDate'] ?? '');
      if (date != null) {
        monthCounts[date.month] = (monthCounts[date.month] ?? 0) + 1;
        dayCounts[date.weekday] = (dayCounts[date.weekday] ?? 0) + 1;
      }
    }

    String busiestMonth = monthCounts.isNotEmpty 
        ? DateFormat('MMMM').format(DateTime(2000, monthCounts.entries.reduce((a, b) => a.value > b.value ? a : b).key)) 
        : "N/A";
    int busiestMonthCount = monthCounts.isNotEmpty ? monthCounts.entries.reduce((a, b) => a.value > b.value ? a : b).value : 0;

    String favoriteDay = dayCounts.isNotEmpty 
        ? ["", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"][dayCounts.entries.reduce((a, b) => a.value > b.value ? a : b).key]
        : "N/A";

    final memories = yearDiary.where((m) => m['userPhoto'] != null && m['userPhoto'].toString().isNotEmpty).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Account Info Box
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF222222), 
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF333333))
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26, 
                  backgroundImage: user.photoURL != null ? NetworkImage(user.photoURL!) : null,
                  backgroundColor: Colors.grey[800],
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(user.displayName ?? 'User', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  Text(user.email ?? '', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ])),
                TextButton(
                  onPressed: widget.onSignOut, 
                  child: const Text('Sign Out', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // 2. Year Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Year in Review', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              Row(
                children: [
                  GestureDetector(
                    onTap: _shareRecap,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFFf09433), Color(0xFFbc1888)]),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text('Share 📸', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: _selectedYear,
                    dropdownColor: const Color(0xFF222222),
                    onChanged: (v) => setState(() => _selectedYear = v!),
                    items: _availableYears.map((y) => DropdownMenuItem(value: y, child: Text(y, style: const TextStyle(color: Colors.white)))).toList(),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 3. SHAREABLE STATS AREA
          Screenshot(
            controller: _screenshotController,
            child: Container(
              color: const Color(0xFF121212), 
              padding: EdgeInsets.symmetric(horizontal: _isSharing ? 24 : 0, vertical: _isSharing ? 32 : 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isSharing) ...[
                    Text('My $_selectedYear Movie Recap', 
                      style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 25),
                  ],
                  Row(
                    children: [
                      Expanded(child: _buildStatCard('MOVIES LOGGED', yearDiary.length.toString(), const LinearGradient(colors: [Color(0xFFE040FB), Color(0xFF7C4DFF)]))),
                      const SizedBox(width: 15),
                      Expanded(child: _buildStatCard('AVG RATING', avgRating.toStringAsFixed(1), const LinearGradient(colors: [Color(0xFFFFB74D), Color(0xFFF57C00)]))),
                    ],
                  ),
                  const SizedBox(height: 15),
                  if (topRated != null) _buildTopRated(topRated),
                  const SizedBox(height: 15),
                  Row(
                    children: [
                      Expanded(child: _buildStatCard('BUSIEST MONTH', busiestMonth, const LinearGradient(colors: [Color(0xFF00c6ff), Color(0xFF0072ff)]), subtitle: '$busiestMonthCount movies')),
                      const SizedBox(width: 15),
                      Expanded(child: _buildStatCard('FAVORITE DAY', favoriteDay, const LinearGradient(colors: [Color(0xFF11998e), Color(0xFF38ef7d)]), subtitle: 'Most active watch day')),
                    ],
                  ),
                  if (_isSharing) ...[
                    const SizedBox(height: 30),
                    const Text('🍿 LOGGED WITH MOVIE TRACKER', 
                      style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                  ],
                ],
              ),
            ),
          ),

          // 4. SQUARE POLAROID MEMORIES
          if (memories.isNotEmpty) ...[
            const SizedBox(height: 32),
            Text('Moments of $_selectedYear', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            const Divider(color: Color(0xFF333333), height: 24),
            SizedBox(
              height: 240,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: memories.length,
                itemBuilder: (context, index) {
                  final m = memories[index];
                  return Transform.rotate(
                    angle: index % 2 == 0 ? -0.04 : 0.04,
                    child: Container(
                      width: 170,
                      margin: const EdgeInsets.only(right: 16, top: 10, bottom: 10),
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 8, offset: Offset(2, 4))]
                      ),
                      child: Column(
                        children: [
                          AspectRatio(
                            aspectRatio: 1, 
                            child: Container(color: Colors.black, child: _buildMemoryImage(m['userPhoto'])),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            m['title'] ?? '',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.black, fontSize: 14, fontFamily: 'cursive', fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],

          // 5. AMC STUBS CALCULATOR (At bottom)
          const SizedBox(height: 32),
          AmcStubsCard(
            diary: widget.diary,
            watchlist: widget.watchlist,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String val, Gradient g, {String? subtitle}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(gradient: g, borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, 
        children: [
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(val, style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold, height: 1)),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(subtitle, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
          ]
        ]
      ),
    );
  }

  Widget _buildTopRated(Map<String, dynamic> movie) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF651FFF), Color(0xFF311B92)]), 
        borderRadius: BorderRadius.circular(18)
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('TOP RATED WATCH', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
          const SizedBox(height: 15),
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8), 
                child: Image.network(
                  'https://image.tmdb.org/t/p/w200${movie['posterPath']}', 
                  width: 65, height: 95, fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(width: 65, height: 95, color: Colors.black38),
                )
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, 
                  children: [
                    Text(movie['title'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        const Icon(Icons.star, color: Color(0xFFf5c518), size: 20),
                        const SizedBox(width: 6),
                        Text(movie['rating'].toStringAsFixed(1), style: const TextStyle(color: Color(0xFFf5c518), fontWeight: FontWeight.bold, fontSize: 20)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
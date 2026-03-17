import 'package:flutter/material.dart';
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/intl.dart';

import 'tmdb_service.dart';
import 'movie_details_dialog.dart';
import 'storage_service.dart';
import 'my_movies_drawer.dart';
import 'firebase_options.dart';
import 'firebase_service.dart';
import 'auth_dialog.dart';
import 'notification_service.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:permission_handler/permission_handler.dart'; // <-- 1. ADD THIS IMPORT

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await NotificationService().init();

  // --- 2. ADD THIS PERMISSION CHECK ---
  // If the exact alarm permission is denied, this will automatically
  // route you to the correct Android settings page to flip the switch.
  if (await Permission.scheduleExactAlarm.isDenied) {
    await Permission.scheduleExactAlarm.request();
  }
  // ------------------------------------

  await AndroidAlarmManager.initialize();

  runApp(const MovieTrackerApp());
}

class MovieTrackerApp extends StatelessWidget {
  const MovieTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Movie Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        primaryColor: const Color(0xFFE50914),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE50914),
          secondary: Color(0xFF2B2B2B),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          elevation: 0,
          shape: Border(bottom: BorderSide(color: Color(0xFF333333), width: 1)),
        ),
        fontFamily: 'Segoe UI',
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  List<dynamic> _movies = [];
  bool _isLoading = true;
  int _watchlistCount = 0;
  DateTime _currentViewDate = DateTime.now();
  Map<String, dynamic>? _upNextMovie;

  final TextEditingController _searchController = TextEditingController();
  final TMDBService _tmdbService = TMDBService();
  final FirebaseService _firebaseService = FirebaseService();
  final StorageService _storageService = StorageService();
  final NotificationService _notificationService = NotificationService();

  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;
  bool _hasInternet = true;

  @override
  void initState() {
    super.initState();
    _checkInitialConnectivity();

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) {
      if (mounted) {
        setState(() {
          _hasInternet = !results.contains(ConnectivityResult.none);
        });
      }
    });

    _loadMovies();
    _updateLocalData();
    _pullCloudDataToLocal();
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _checkInitialConnectivity() async {
    final results = await Connectivity().checkConnectivity();
    if (mounted) {
      setState(() {
        _hasInternet = !results.contains(ConnectivityResult.none);
      });
    }
  }

  Future<void> _loadMovies() async {
    setState(() => _isLoading = true);
    final movies = await _tmdbService.fetchCurrentMonthMovies(_currentViewDate);
    if (mounted) {
      setState(() {
        _movies = movies;
        _isLoading = false;
      });
    }
  }

  Future<void> _onSearchChanged(String query) async {
    if (query.isEmpty) {
      _loadMovies();
      return;
    }
    setState(() => _isLoading = true);
    final results = await _tmdbService.searchMovies(query);
    if (mounted) {
      setState(() {
        _movies = results;
        _isLoading = false;
      });
    }
  }

  void _changeMonth(int offset) {
    setState(() {
      _currentViewDate = DateTime(
        _currentViewDate.year,
        _currentViewDate.month + offset,
      );
      _searchController.clear();
    });
    _loadMovies();
  }

  Future<void> _selectMonthYear() async {
    int selectedYear = _currentViewDate.year;
    int selectedMonth = _currentViewDate.month;

    final DateTime? picked = await showDialog<DateTime>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E1E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_left, color: Colors.white),
                    onPressed: () => setDialogState(() => selectedYear--),
                  ),
                  Text(
                    selectedYear.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_right, color: Colors.white),
                    onPressed: () => setDialogState(() => selectedYear++),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 1.5,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: 12,
                  itemBuilder: (context, index) {
                    final monthName = DateFormat(
                      'MMM',
                    ).format(DateTime(2000, index + 1));
                    final isSelected = selectedMonth == index + 1;
                    return InkWell(
                      onTap: () {
                        Navigator.pop(
                          context,
                          DateTime(selectedYear, index + 1),
                        );
                      },
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFFE50914)
                              : const Color(0xFF2B2B2B),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFFE50914)
                                : const Color(0xFF444444),
                          ),
                        ),
                        child: Text(
                          monthName,
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.grey,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );

    if (picked != null && picked != _currentViewDate) {
      setState(() {
        _currentViewDate = picked;
        _searchController.clear();
      });
      _loadMovies();
    }
  }

  Future<void> _updateLocalData() async {
    final watchlist = await _storageService.getWatchlist();

    if (watchlist.isEmpty) {
      if (mounted) {
        setState(() {
          _watchlistCount = 0;
          _upNextMovie = null;
        });
      }
      return;
    }

    Map<String, dynamic>? nextMovie;
    DateTime today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );

    List<Map<String, dynamic>> futureMovies = [];
    List<Map<String, dynamic>> pastMovies = [];

    for (var m in watchlist) {
      final String rDateStr = (m['releaseDate'] ?? m['release_date'] ?? '')
          .toString();

      if (rDateStr.isNotEmpty) {
        DateTime? rDate = DateTime.tryParse(rDateStr);
        if (rDate != null) {
          DateTime normalizedDate = DateTime(
            rDate.year,
            rDate.month,
            rDate.day,
          );
          if (normalizedDate.compareTo(today) >= 0) {
            futureMovies.add(m);
          } else {
            pastMovies.add(m);
          }
        }
      }
    }

    if (futureMovies.isNotEmpty) {
      futureMovies.sort((a, b) {
        final dateA =
            DateTime.tryParse(
              (a['releaseDate'] ?? a['release_date'] ?? '').toString(),
            ) ??
            DateTime(2099);
        final dateB =
            DateTime.tryParse(
              (b['releaseDate'] ?? b['release_date'] ?? '').toString(),
            ) ??
            DateTime(2099);
        return dateA.compareTo(dateB);
      });
      nextMovie = futureMovies.first;
    } else if (pastMovies.isNotEmpty) {
      pastMovies.sort((a, b) {
        final dateA =
            DateTime.tryParse(
              (a['releaseDate'] ?? a['release_date'] ?? '').toString(),
            ) ??
            DateTime(1900);
        final dateB =
            DateTime.tryParse(
              (b['releaseDate'] ?? b['release_date'] ?? '').toString(),
            ) ??
            DateTime(1900);
        return dateB.compareTo(dateA);
      });
      nextMovie = pastMovies.first;
    } else {
      nextMovie = watchlist.last;
    }

    if (mounted) {
      setState(() {
        _watchlistCount = watchlist.length;
        _upNextMovie = nextMovie;
      });
    }
  }

  Future<void> _syncLocalDataToCloud() async {
    if (_firebaseService.currentUser == null || !_hasInternet) return;
    try {
      final watchlist = await _storageService.getWatchlist();
      final diary = await _storageService.getDiary();
      final tickets = await _storageService.getTickets();
      await _firebaseService.syncToCloud(
        watchlist: watchlist,
        diary: diary,
        tickets: tickets,
      );
    } catch (e) {
      debugPrint('Sync failed: $e');
    }
  }

  // Inside your refresh/save function
  void refreshNotifications(Map<String, dynamic> movie) async {
    // 1. Fetch the actual runtime
    int runtime = await _tmdbService.getMovieRuntime(
      int.parse(movie['id'].toString()),
    );

    // 2. Pass that runtime to our new Awesome Notification flow
    await _notificationService.scheduleMovieFlow(movie, runtime);

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Theater Flow Updated! 🎬')));
    }
  }

  Future<void> _pullCloudDataToLocal() async {
    if (_firebaseService.currentUser == null || !_hasInternet) return;
    final cloudData = await _firebaseService.fetchUserData();
    if (cloudData != null) {
      if (cloudData['watchlist'] != null) {
        await _storageService.saveWatchlist(
          List<dynamic>.from(cloudData['watchlist']),
        );
      }
      if (cloudData['diary'] != null) {
        await _storageService.saveDiary(List<dynamic>.from(cloudData['diary']));
      }
      if (cloudData['tickets'] != null) {
        await _storageService.saveTickets(
          List<dynamic>.from(cloudData['tickets']),
        );
      }
      await _updateLocalData();
      if (mounted) setState(() {});
    }
  }

  Widget _buildMonthChooser() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF2B2B2B),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF444444),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            icon: const Icon(
              Icons.keyboard_double_arrow_left,
              size: 16,
              color: Colors.white,
            ),
            onPressed: () => _changeMonth(-1),
          ),
          InkWell(
            onTap: _selectMonthYear,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              child: Row(
                children: [
                  Text(
                    DateFormat('MMMM yyyy').format(_currentViewDate),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.keyboard_arrow_down,
                    size: 16,
                    color: Colors.grey,
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF444444),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            icon: const Icon(
              Icons.keyboard_double_arrow_right,
              size: 16,
              color: Colors.white,
            ),
            onPressed: () => _changeMonth(1),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String upNextDate = 'TBD';
    if (_upNextMovie != null) {
      upNextDate =
          (_upNextMovie!['releaseDate'] ??
                  _upNextMovie!['release_date'] ??
                  'TBD')
              .toString();
      if (upNextDate != 'TBD' && upNextDate.length >= 10) {
        try {
          DateTime parsed = DateTime.parse(upNextDate);
          upNextDate = '${parsed.month}/${parsed.day}/${parsed.year}';
        } catch (e) {
          debugPrint('Date formatting error: $e');
        }
      }
    }

    return Scaffold(
      onEndDrawerChanged: (isOpened) {
        if (!isOpened) {
          _updateLocalData();
        }
      },
      appBar: AppBar(
        title: StreamBuilder(
          stream: _firebaseService.authStateChanges,
          builder: (context, snapshot) {
            final user = snapshot.data;
            final isLoggedIn = user != null;
            final firstName = user?.displayName?.split(' ')[0] ?? 'Guest';

            Color dotColor;
            String statusText;

            if (!isLoggedIn) {
              dotColor = Colors.grey;
              statusText = 'Not Logged In';
            } else if (!_hasInternet) {
              dotColor = Colors.redAccent;
              statusText = 'Offline Mode';
            } else {
              dotColor = Colors.greenAccent;
              statusText = 'Connected to Cloud';
            }

            Widget avatarStack = Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: const Color(0xFF333333),
                  backgroundImage: user?.photoURL != null
                      ? NetworkImage(user!.photoURL!)
                      : null,
                  child: user?.photoURL == null
                      ? const Icon(Icons.person, color: Colors.grey)
                      : null,
                ),
                Positioned(
                  bottom: -2,
                  right: -2,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black, width: 2.5),
                    ),
                  ),
                ),
              ],
            );

            return Row(
              children: [
                if (isLoggedIn)
                  PopupMenuButton<String>(
                    color: const Color(0xFF2B2B2B),
                    offset: const Offset(0, 45),
                    onSelected: (value) {
                      if (value == 'logout') {
                        _firebaseService.signOut();
                      } else if (value == 'sync_push') {
                        _syncLocalDataToCloud();
                      } else if (value == 'sync_pull') {
                        _pullCloudDataToLocal();
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        enabled: false,
                        child: Text(
                          user.email ?? '',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'sync_pull',
                        child: Row(
                          children: [
                            Icon(
                              Icons.cloud_download,
                              size: 18,
                              color: Colors.white,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Restore from Cloud',
                              style: TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'sync_push',
                        child: Row(
                          children: [
                            Icon(
                              Icons.cloud_upload,
                              size: 18,
                              color: Colors.white,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Backup to Cloud',
                              style: TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'logout',
                        child: Row(
                          children: [
                            Icon(Icons.logout, size: 18, color: Colors.white),
                            SizedBox(width: 8),
                            Text(
                              'Sign Out',
                              style: TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ],
                    child: avatarStack,
                  )
                else
                  GestureDetector(
                    onTap: () => showDialog(
                      context: context,
                      builder: (context) => const AuthDialog(),
                    ),
                    child: avatarStack,
                  ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: isLoggedIn
                      ? null
                      : () => showDialog(
                          context: context,
                          builder: (context) => const AuthDialog(),
                        ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Hi, $firstName',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        statusText,
                        style: TextStyle(
                          fontSize: 10,
                          color: dotColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            child: Builder(
              builder: (context) => OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  backgroundColor: const Color(0xFF2B2B2B),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  side: const BorderSide(color: Color(0xFF444444)),
                ),
                onPressed: () => Scaffold.of(context).openEndDrawer(),
                icon: const Icon(Icons.menu, size: 18),
                label: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE50914),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$_watchlistCount',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      endDrawer: const MyMoviesDrawer(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_upNextMovie != null)
              GestureDetector(
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (context) => MovieDetailsDialog(
                      movieId: int.parse(_upNextMovie!['id'].toString()),
                    ),
                  );
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    border: Border.all(
                      color: const Color(0xFFE50914).withValues(alpha: 0.5),
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFE50914).withValues(alpha: 0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: _upNextMovie!['posterPath'] != null
                            ? Image.network(
                                'https://image.tmdb.org/t/p/w200${_upNextMovie!['posterPath']}',
                                width: 60,
                                height: 90,
                                fit: BoxFit.cover,
                              )
                            : Container(
                                width: 60,
                                height: 90,
                                color: Colors.grey[800],
                                child: const Icon(
                                  Icons.movie,
                                  color: Colors.white54,
                                ),
                              ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE50914),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'UP NEXT IN WATCHLIST',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _upNextMovie!['title'] ?? 'Unknown',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Releasing: $upNextDate',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 24),

            TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search for any movie...',
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                filled: true,
                fillColor: const Color(0xFF2B2B2B),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 24),

            if (_searchController.text.isEmpty) ...[
              _buildMonthChooser(),
              const SizedBox(height: 16),
            ],

            _isLoading
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFFE50914),
                      ),
                    ),
                  )
                : _movies.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Text(
                        'No movies found.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                : GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          childAspectRatio: 0.46,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 16,
                        ),
                    itemCount: _movies.length,
                    itemBuilder: (context, index) {
                      return MovieCard(
                        key: ValueKey(_movies[index]['id']),
                        movieData: _movies[index],
                        onSyncNeeded: () {
                          _updateLocalData();
                          _syncLocalDataToCloud();
                        },
                      );
                    },
                  ),

            if (_searchController.text.isEmpty &&
                !_isLoading &&
                _movies.isNotEmpty) ...[
              const SizedBox(height: 24),
              _buildMonthChooser(),
              const SizedBox(height: 24),
            ],
          ],
        ),
      ),
    );
  }
}

class MovieCard extends StatefulWidget {
  final Map<String, dynamic> movieData;
  final VoidCallback onSyncNeeded;
  const MovieCard({
    super.key,
    required this.movieData,
    required this.onSyncNeeded,
  });

  @override
  State<MovieCard> createState() => _MovieCardState();
}

class _MovieCardState extends State<MovieCard> {
  final StorageService _storageService = StorageService();
  bool _isInWatchlist = false;

  @override
  void initState() {
    super.initState();
    _checkIfAdded();
  }

  Future<void> _checkIfAdded() async {
    final watchlist = await _storageService.getWatchlist();
    if (mounted) {
      setState(() {
        _isInWatchlist = watchlist.any(
          (m) => m['id'].toString() == widget.movieData['id'].toString(),
        );
      });
    }
  }

  Future<void> _addToWatchlist() async {
    await _storageService.addToWatchlist(widget.movieData);
    if (mounted) {
      setState(() => _isInWatchlist = true);
      widget.onSyncNeeded();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Added to Watchlist!'),
          backgroundColor: Color(0xFF34A853),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final posterPath = widget.movieData['poster_path'];
    final imageUrl = posterPath != null
        ? 'https://image.tmdb.org/t/p/w500$posterPath'
        : '';

    final rawDate = widget.movieData['release_date'] ?? '';
    String displayDate = 'TBD';
    if (rawDate.isNotEmpty && rawDate.length >= 10) {
      try {
        DateTime parsed = DateTime.parse(rawDate);
        displayDate = '${parsed.month}/${parsed.day}/${parsed.year}';
      } catch (e) {
        displayDate = rawDate;
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => showDialog(
                context: context,
                builder: (context) =>
                    MovieDetailsDialog(movieId: widget.movieData['id']),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: imageUrl.isNotEmpty
                    ? Image.network(imageUrl, fit: BoxFit.cover)
                    : Container(
                        color: Colors.grey[800],
                        child: const Icon(Icons.movie, color: Colors.grey),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.movieData['title'] ?? 'Unknown',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            displayDate,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Color(0xFFE50914),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE50914),
              disabledBackgroundColor: const Color(0xFF555555),
              padding: EdgeInsets.zero,
              minimumSize: const Size(double.infinity, 32),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            onPressed: _isInWatchlist ? null : _addToWatchlist,
            child: Text(
              _isInWatchlist ? 'Added' : '+Add',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: _isInWatchlist ? const Color(0xFFAAAAAA) : Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

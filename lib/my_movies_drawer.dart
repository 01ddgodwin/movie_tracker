import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'storage_service.dart';
import 'add_plan_dialog.dart';
import 'rating_dialog.dart';
import 'firebase_service.dart';
import 'friend_profile_dialog.dart';
import 'profile_tab.dart';
import 'movie_details_dialog.dart';
import 'share_preview_dialog.dart';
import 'notification_service.dart'; // Added

class MyMoviesDrawer extends StatefulWidget {
  const MyMoviesDrawer({super.key});
  @override
  State<MyMoviesDrawer> createState() => _MyMoviesDrawerState();
}

class _MyMoviesDrawerState extends State<MyMoviesDrawer> {
  final StorageService _storageService = StorageService();
  final FirebaseService _firebaseService = FirebaseService();
  final TextEditingController _friendCodeController = TextEditingController();

  List<dynamic> _watchlist = [];
  List<dynamic> _diary = [];
  List<dynamic> _tickets = [];
  List<dynamic> _plans = [];
  List<dynamic> _friendTickets = [];
  List<dynamic> _friendsList = [];
  String _myFriendCode = 'Loading...';

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _friendCodeController.dispose();
    super.dispose();
  }

  void _showLoadingOverlay() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: Color(0xFFE50914)),
      ),
    );
  }

  void _hideLoadingOverlay() {
    Navigator.of(context, rootNavigator: true).pop();
  }

  String _formatDateMDY(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return 'TBD';
    try {
      final parsed = DateFormat('MMMM d, yyyy').parse(dateStr);
      return DateFormat('M/d/yyyy').format(parsed);
    } catch (_) {}
    try {
      final parsed = DateFormat('MM/dd/yyyy').parse(dateStr);
      return DateFormat('M/d/yyyy').format(parsed);
    } catch (_) {}
    try {
      final parsed = DateTime.parse(dateStr);
      return DateFormat('M/d/yyyy').format(parsed);
    } catch (_) {
      return dateStr;
    }
  }

  String _formatTimeAMPM(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return 'TBD';
    try {
      final lower = timeStr.toLowerCase();
      if (lower.contains('am') || lower.contains('pm')) {
        final parsed = DateFormat.jm().parse(timeStr);
        return DateFormat.jm().format(parsed);
      } else {
        final parts = timeStr.split(':');
        final d = DateTime(
          2000,
          1,
          1,
          int.parse(parts[0]),
          int.parse(parts[1]),
        );
        return DateFormat.jm().format(d);
      }
    } catch (_) {
      return timeStr;
    }
  }

  bool _isPast(String? dateStr, String? timeStr, [String? planTitle]) {
    if (dateStr == null || dateStr.isEmpty) return false;
    try {
      String cleanDate = dateStr.trim();
      String cleanTime = timeStr?.trim() ?? "12:00 PM";

      // 1. Parse Date
      DateTime eventDate;
      try {
        eventDate = DateFormat('MMMM d, yyyy').parse(cleanDate);
      } catch (_) {
        try {
          eventDate = DateFormat('M/d/yyyy').parse(cleanDate);
        } catch (_) {
          eventDate = DateTime.parse(cleanDate);
        }
      }

      // 2. Parse Time with manual AM/PM override
      int hour = 0;
      int minute = 0;

      try {
        // Try the standard parser first
        final timeParsed = DateFormat.jm().parse(cleanTime);
        hour = timeParsed.hour;
        minute = timeParsed.minute;
      } catch (_) {
        // Manual fallback for strings like "11:00 PM" or "23:00"
        final parts = cleanTime.split(':');
        if (parts.length >= 2) {
          hour = int.parse(parts[0].replaceAll(RegExp(r'[^0-9]'), ''));
          minute = int.parse(
            parts[1].replaceAll(RegExp(r'[^0-9]'), '').substring(0, 2),
          );

          // Manual PM shift if parser failed
          if (cleanTime.toUpperCase().contains("PM") && hour < 12) {
            hour += 12;
          } else if (cleanTime.toUpperCase().contains("AM") && hour == 12) {
            hour = 0;
          }
        }
      }

      final preciseEventStart = DateTime(
        eventDate.year,
        eventDate.month,
        eventDate.day,
        hour,
        minute,
      );

      final now = DateTime.now();
      final archiveThreshold = preciseEventStart.add(const Duration(hours: 1));
      bool shouldArchive = now.isAfter(archiveThreshold);

      // --- THE DEBUG AUDIT ---
      // debugPrint("========================================");
      // debugPrint("AUDIT FOR: ${planTitle ?? 'Unknown Movie'}");
      // debugPrint("PARSED AS: $preciseEventStart (24hr format)");
      // debugPrint("CURRENT TIME: $now");
      // debugPrint("RESULT: ${shouldArchive ? 'ARCHIVE' : 'UPCOMING'}");
      // debugPrint("========================================");

      return shouldArchive;
    } catch (e) {
      debugPrint("Archive Check Error: $e");
      return false;
    }
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    List<dynamic> tempPlans = [];
    List<dynamic> tempFriendTickets = [];
    List<dynamic> tempFriends = [];
    String code = 'Not Generated';

    try {
      if (_firebaseService.currentUser != null) {
        final cloudData = await _firebaseService.fetchUserData();
        if (cloudData != null) {
          if (cloudData['watchlist'] != null) {
            await _storageService.saveWatchlist(
              List<dynamic>.from(cloudData['watchlist']),
            );
          }
          if (cloudData['diary'] != null) {
            await _storageService.saveDiary(
              List<dynamic>.from(cloudData['diary']),
            );
          }
          if (cloudData['tickets'] != null) {
            await _storageService.saveTickets(
              List<dynamic>.from(cloudData['tickets']),
            );
          }
          if (cloudData['plans'] != null)
            tempPlans.addAll(List<dynamic>.from(cloudData['plans']));
          if (cloudData['sharedPlans'] != null)
            tempPlans.addAll(List<dynamic>.from(cloudData['sharedPlans']));
          if (cloudData['friendTickets'] != null)
            tempFriendTickets.addAll(
              List<dynamic>.from(cloudData['friendTickets']),
            );
          if (cloudData['friendsList'] != null)
            tempFriends = List<dynamic>.from(cloudData['friendsList']);
          if (cloudData['friendCode'] != null) code = cloudData['friendCode'];

          tempPlans.sort((a, b) {
            final dateA = DateTime.tryParse('${a['date']}') ?? DateTime(2099);
            final dateB = DateTime.tryParse('${b['date']}') ?? DateTime(2099);
            return dateA.compareTo(dateB);
          });
        }
      }

      final watchlistData = await _storageService.getWatchlist();
      final diaryData = await _storageService.getDiary();
      final ticketData = await _storageService.getTickets();

      // --- BULLETPROOF WEB GUARD ---
      if (!kIsWeb) {
        final notifService = NotificationService();
        await notifService.init();

        // 1. Schedule notifications for upcoming plans
        final upcomingPlans = tempPlans
            .where((p) => !_isPast(p['date'], p['time']))
            .toList();
        for (var plan in upcomingPlans) {
          try {
            await notifService.scheduleMovieFlow(plan, 120);
          } catch (e) {
            debugPrint("Plan Notification Error: $e");
          }
        }

        // 2. Schedule for Standalone Tickets
        final upcomingStandaloneTickets = ticketData
            .where(
              (t) =>
                  !_isPast(t['date'], t['time']) &&
                  (t['planId'] == null || t['planId'] == 'null'),
            )
            .toList();
        for (var ticket in upcomingStandaloneTickets) {
          try {
            await notifService.scheduleMovieFlow(ticket, 120);
          } catch (e) {
            debugPrint("Ticket Notification Error: $e");
          }
        }
      }
      // -------------------------------

      diaryData.sort((a, b) {
        final dateA =
            DateTime.tryParse((a['watchedDate'] ?? '').toString()) ??
            DateTime(2000);
        final dateB =
            DateTime.tryParse((b['watchedDate'] ?? '').toString()) ??
            DateTime(2000);
        return dateB.compareTo(dateA);
      });

      if (mounted) {
        setState(() {
          _watchlist = watchlistData;
          _diary = diaryData;
          _tickets = ticketData;
          _plans = tempPlans;
          _friendTickets = tempFriendTickets;
          _friendsList = tempFriends;
          _myFriendCode = code;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Load Data Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showAttachTicketModal(String planId) {
    final availableTickets = _tickets.where((t) {
      final pId = t['planId']?.toString() ?? '';
      if (pId.isEmpty || pId == 'null') return true;
      final planExists = _plans.any((p) => p['id'].toString() == pId);
      return !planExists;
    }).toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        if (availableTickets.isEmpty) {
          return const SizedBox(
            height: 200,
            child: Center(
              child: Text(
                'No unattached tickets available.\nSave a new ticket first!',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ),
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'Select a Ticket to Attach',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: availableTickets.length,
                itemBuilder: (context, index) {
                  final t = availableTickets[index];
                  return ListTile(
                    leading: const Icon(
                      Icons.confirmation_num,
                      color: Color(0xFFE50914),
                    ),
                    title: Text(
                      t['title'] ?? t['movie'] ?? 'Unknown Movie',
                      style: const TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      '${_formatDateMDY(t['date'])} @ ${_formatTimeAMPM(t['time'])}',
                      style: const TextStyle(color: Colors.grey),
                    ),
                    trailing: const Icon(
                      Icons.add_circle_outline,
                      color: Colors.grey,
                    ),
                    onTap: () async {
                      Navigator.pop(context);
                      await _attachTicketToPlan(t['id'].toString(), planId);
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _attachTicketToPlan(String ticketId, String planId) async {
    _showLoadingOverlay();
    try {
      List<dynamic> allTickets = await _storageService.getTickets();
      for (var t in allTickets) {
        if (t['id'].toString() == ticketId) {
          t['planId'] = planId;
          break;
        }
      }
      await _storageService.saveTickets(allTickets);
      if (_firebaseService.currentUser != null) {
        await _firebaseService.syncToCloud(
          watchlist: _watchlist,
          diary: _diary,
          tickets: allTickets,
        );
      }
      await _loadData();
    } finally {
      _hideLoadingOverlay();
    }
  }

  Future<void> _detachTicket(String ticketId) async {
    _showLoadingOverlay();
    try {
      List<dynamic> allTickets = await _storageService.getTickets();
      for (var t in allTickets) {
        if (t['id'].toString() == ticketId) {
          t.remove('planId');
          break;
        }
      }
      await _storageService.saveTickets(allTickets);
      if (_firebaseService.currentUser != null) {
        await _firebaseService.syncToCloud(
          watchlist: _watchlist,
          diary: _diary,
          tickets: allTickets,
        );
      }
      await _loadData();
    } finally {
      _hideLoadingOverlay();
    }
  }

  Future<void> _removeTicketItem(String id) async {
    bool? confirm = await showDialog(
      context: context,
      builder: (context) => _buildConfirmDialog(
        'Delete Ticket?',
        'Are you sure you want to permanently remove this ticket?',
      ),
    );
    if (confirm == true) {
      _showLoadingOverlay();
      try {
        await _storageService.removeTicket(id);
        if (_firebaseService.currentUser != null) {
          final w = await _storageService.getWatchlist();
          final d = await _storageService.getDiary();
          final t = await _storageService.getTickets();
          await _firebaseService.syncToCloud(
            watchlist: w,
            diary: d,
            tickets: t,
          );
        }
        await _loadData();
      } finally {
        _hideLoadingOverlay();
      }
    }
  }

  Future<void> _deletePlan(String planId) async {
    bool? confirm = await showDialog(
      context: context,
      builder: (context) => _buildConfirmDialog(
        'Delete Plan?',
        'This will delete the plan for everyone invited.',
      ),
    );
    if (confirm == true) {
      _showLoadingOverlay();
      try {
        await _firebaseService.deletePlan(planId);
        await _loadData();
      } finally {
        _hideLoadingOverlay();
      }
    }
  }

  Future<void> _leavePlan(String planId) async {
    bool? confirm = await showDialog(
      context: context,
      builder: (context) => _buildConfirmDialog(
        'Leave Plan?',
        'You will no longer be part of this movie night.',
      ),
    );
    if (confirm == true) {
      _showLoadingOverlay();
      try {
        await _firebaseService.leavePlan(planId);
        await _loadData();
      } finally {
        _hideLoadingOverlay();
      }
    }
  }

  Future<void> _removeWatchlistItem(String id) async {
    _showLoadingOverlay();
    try {
      await _storageService.removeFromWatchlist(id);
      if (_firebaseService.currentUser != null) {
        final w = await _storageService.getWatchlist();
        final d = await _storageService.getDiary();
        final t = await _storageService.getTickets();
        await _firebaseService.syncToCloud(watchlist: w, diary: d, tickets: t);
      }
      await _loadData();
    } finally {
      _hideLoadingOverlay();
    }
  }

  Future<void> _removeDiaryItem(String id) async {
    bool? confirm = await showDialog(
      context: context,
      builder: (context) => _buildConfirmDialog(
        'Delete Entry?',
        'Are you sure you want to remove this movie from your diary?',
      ),
    );
    if (confirm == true) {
      _showLoadingOverlay();
      try {
        await _storageService.removeFromDiary(id);
        if (_firebaseService.currentUser != null) {
          await _firebaseService.deleteDiaryEntry(id);
        }
        await _loadData();
      } finally {
        _hideLoadingOverlay();
      }
    }
  }

  Widget _buildConfirmDialog(String title, String content) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      content: Text(content, style: const TextStyle(color: Colors.grey)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text(
            'Confirm',
            style: TextStyle(color: Colors.redAccent),
          ),
        ),
      ],
    );
  }

  void _viewMemoryPhoto(String title, String imagePath) {
    Widget imageWidget;
    if (imagePath.startsWith('http')) {
      imageWidget = Image.network(
        imagePath,
        fit: BoxFit.cover,
        errorBuilder: (c, e, s) =>
            const Icon(Icons.broken_image, size: 50, color: Colors.grey),
      );
    } else if (imagePath.startsWith('data:image')) {
      try {
        final base64Str = imagePath.split(',').last;
        imageWidget = Image.memory(
          base64Decode(base64Str),
          fit: BoxFit.cover,
          errorBuilder: (c, e, s) =>
              const Icon(Icons.broken_image, size: 50, color: Colors.grey),
        );
      } catch (e) {
        imageWidget = const Icon(
          Icons.broken_image,
          size: 50,
          color: Colors.grey,
        );
      }
    } else {
      imageWidget = Image.file(
        File(imagePath),
        fit: BoxFit.cover,
        errorBuilder: (c, e, s) =>
            const Icon(Icons.broken_image, size: 50, color: Colors.grey),
      );
    }
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF1E1E1E),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: imageWidget,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _enlargeQR(String qrData) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Scan Ticket',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  InkWell(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.close, color: Colors.black),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _buildQrImage(qrData, size: 250),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQrImage(String data, {double size = 70}) {
    if (data.isEmpty)
      return Icon(Icons.qr_code, size: size, color: Colors.black);
    if (data.startsWith('http'))
      return Image.network(data, width: size, height: size, fit: BoxFit.cover);
    if (data.startsWith('data:image')) {
      try {
        final base64Str = data.split(',').last;
        return Image.memory(
          base64Decode(base64Str),
          width: size,
          height: size,
          fit: BoxFit.cover,
        );
      } catch (e) {
        return Icon(Icons.broken_image, size: size, color: Colors.black);
      }
    }
    return Image.file(
      File(data),
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (c, e, s) =>
          Icon(Icons.qr_code, size: size, color: Colors.black),
    );
  }

  Map<String, List<dynamic>> _getGroupedDiary() {
    Map<String, List<dynamic>> groups = {};
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    for (var movie in _diary) {
      final dateStr = (movie['watchedDate'] ?? '').toString();
      final date = DateTime.tryParse(dateStr) ?? DateTime.now();
      final monthYear = '${months[date.month - 1]} ${date.year}';
      if (!groups.containsKey(monthYear)) groups[monthYear] = [];
      groups[monthYear]!.add(movie);
    }
    return groups;
  }

  Widget _buildTicketCard(Map<String, dynamic> ticket) {
    final qrData = ticket['qr'] ?? ticket['ticketImage'] ?? '';
    final posterPath = ticket['posterPath'];
    final imageUrl = posterPath != null && posterPath != 'null'
        ? 'https://image.tmdb.org/t/p/w200$posterPath'
        : '';

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 16, top: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: imageUrl.isNotEmpty
                            ? Image.network(
                                imageUrl,
                                width: 60,
                                height: 90,
                                fit: BoxFit.cover,
                              )
                            : Container(
                                width: 60,
                                height: 90,
                                color: Colors.grey[300],
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ticket['movie'] ?? ticket['title'] ?? 'Unknown',
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              ticket['theater'] ?? 'Unknown Theater',
                              style: const TextStyle(
                                color: Color(0xFFE50914),
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_formatDateMDY(ticket['date'])} @ ${_formatTimeAMPM(ticket['time'])}',
                              style: const TextStyle(
                                color: Color(0xFF555555),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (ticket['seats'] != null &&
                                ticket['seats'].toString().isNotEmpty)
                              Text(
                                'Seats: ${ticket['seats']}',
                                style: const TextStyle(
                                  color: Color(0xFF555555),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Container(width: 1, height: 100, color: Colors.grey[300]),
              Container(
                width: 110,
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'SCAN ENTRY',
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () => _enlargeQR(qrData),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: _buildQrImage(qrData, size: 65),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Positioned(
          top: 0,
          right: 100,
          child: Container(
            width: 20,
            height: 20,
            decoration: const BoxDecoration(
              color: Color(0xFF1A1A1A),
              shape: BoxShape.circle,
            ),
          ),
        ),
        Positioned(
          bottom: 6,
          right: 100,
          child: Container(
            width: 20,
            height: 20,
            decoration: const BoxDecoration(
              color: Color(0xFF1A1A1A),
              shape: BoxShape.circle,
            ),
          ),
        ),
        Positioned(
          top: -2,
          left: -6,
          child: GestureDetector(
            onTap: () => _removeTicketItem(ticket['id'].toString()),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.9),
                shape: BoxShape.circle,
                boxShadow: const [
                  BoxShadow(color: Colors.black45, blurRadius: 4),
                ],
              ),
              padding: const EdgeInsets.all(6),
              child: const Icon(Icons.close, color: Colors.white, size: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlanCard(Map<String, dynamic> plan) {
    final posterPath = plan['posterPath'];
    final imageUrl = posterPath != null && posterPath != 'null'
        ? 'https://image.tmdb.org/t/p/w200$posterPath'
        : '';
    final isHost = plan['hostUid'] == _firebaseService.currentUser?.uid;

    final myMappedTickets = _tickets
        .map(
          (t) => {
            ...t,
            'addedBy': 'You',
            'addedByAvatar': _firebaseService.currentUser?.photoURL,
          },
        )
        .toList();
    final allTickets = [...myMappedTickets, ..._friendTickets];
    final relatedTickets = allTickets
        .where((t) => t['planId'].toString() == plan['id'].toString())
        .toList();

    List<Widget> avatarWidgets = [];
    Widget buildAvatar(String? url) => CircleAvatar(
      radius: 12,
      backgroundColor: Colors.grey[800],
      backgroundImage: url != null && url.isNotEmpty ? NetworkImage(url) : null,
      child: url == null || url.isEmpty
          ? const Icon(Icons.person, size: 14, color: Colors.white)
          : null,
    );

    if (isHost) {
      avatarWidgets.add(buildAvatar(_firebaseService.currentUser?.photoURL));
    } else {
      final host = _friendsList.cast<Map<String, dynamic>>().firstWhere(
        (f) => f['uid'] == plan['hostUid'],
        orElse: () => <String, dynamic>{},
      );
      if (host.isNotEmpty) avatarWidgets.add(buildAvatar(host['photoURL']));
    }

    final invitedUids = List<String>.from(plan['invitedUids'] ?? []);
    for (String uid in invitedUids) {
      if (uid == _firebaseService.currentUser?.uid) {
        avatarWidgets.add(buildAvatar(_firebaseService.currentUser?.photoURL));
      } else {
        final friend = _friendsList.cast<Map<String, dynamic>>().firstWhere(
          (f) => f['uid'] == uid,
          orElse: () => <String, dynamic>{},
        );
        if (friend.isNotEmpty)
          avatarWidgets.add(buildAvatar(friend['photoURL']));
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2B2B2B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isHost
              ? const Color(0xFF444444)
              : Colors.blueAccent.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: imageUrl.isNotEmpty
                    ? Image.network(
                        imageUrl,
                        width: 60,
                        height: 90,
                        fit: BoxFit.cover,
                      )
                    : Container(width: 60, height: 90, color: Colors.grey[800]),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isHost
                                ? Colors.grey[800]
                                : Colors.blueAccent.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            isHost
                                ? 'Hosting'
                                : 'Invited by ${plan['hostName'] ?? 'Friend'}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const Spacer(),
                        if (avatarWidgets.isNotEmpty)
                          SizedBox(
                            height: 28,
                            width: (avatarWidgets.length * 14.0) + 14,
                            child: Stack(
                              children: List.generate(
                                avatarWidgets.length,
                                (index) => Positioned(
                                  right: index * 14.0,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: const Color(0xFF2B2B2B),
                                        width: 2,
                                      ),
                                    ),
                                    child: avatarWidgets[index],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      plan['title'] ?? 'Unknown',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_formatDateMDY(plan['date'])} @ ${_formatTimeAMPM(plan['time'])}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Text('📍', style: TextStyle(fontSize: 12)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            plan['location'] ?? 'TBD',
                            style: const TextStyle(
                              color: Color(0xFFF5C518),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (relatedTickets.isNotEmpty) ...[
            const SizedBox(height: 16),
            SizedBox(
              height: 60,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: relatedTickets.length,
                itemBuilder: (context, index) {
                  final t = relatedTickets[index];
                  final qrData = t['qr'] ?? t['ticketImage'] ?? '';
                  final avatarUrl = t['addedByAvatar']?.toString();
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(right: 12),
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.5),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            GestureDetector(
                              onTap: () => _enlargeQR(qrData),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: _buildQrImage(qrData, size: 40),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text(
                                  'Ticket',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (t['seats'] != null &&
                                    t['seats'].toString().isNotEmpty)
                                  Text(
                                    t['seats'],
                                    style: const TextStyle(
                                      color: Color(0xFFf5c518),
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 6,
                                      backgroundColor: Colors.grey[300],
                                      backgroundImage:
                                          avatarUrl != null &&
                                              avatarUrl.isNotEmpty
                                          ? NetworkImage(avatarUrl)
                                          : null,
                                      child:
                                          avatarUrl == null || avatarUrl.isEmpty
                                          ? const Icon(
                                              Icons.person,
                                              size: 8,
                                              color: Colors.grey,
                                            )
                                          : null,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      t['addedBy'] ?? 'Unknown',
                                      style: const TextStyle(
                                        color: Colors.black54,
                                        fontSize: 9,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (t['addedBy'] == 'You')
                        Positioned(
                          top: -4,
                          right: 8,
                          child: GestureDetector(
                            onTap: () => _detachTicket(t['id'].toString()),
                            child: Container(
                              decoration: const BoxDecoration(
                                color: Colors.redAccent,
                                shape: BoxShape.circle,
                              ),
                              padding: const EdgeInsets.all(4),
                              child: const Icon(
                                Icons.close,
                                size: 10,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => _showAttachTicketModal(plan['id'].toString()),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '🎟️ Attach Ticket',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
              if (isHost) ...[
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.grey, size: 22),
                  onPressed: () => showDialog(
                    context: context,
                    builder: (context) => AddPlanDialog(existingPlan: plan),
                  ).then((_) => _loadData()),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Colors.redAccent,
                    size: 22,
                  ),
                  onPressed: () => _deletePlan(plan['id']),
                ),
              ] else ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => _leavePlan(plan['id']),
                  child: const Text(
                    'Leave',
                    style: TextStyle(
                      color: Colors.orangeAccent,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWatchlistCard(dynamic movie) {
    final posterPath = movie['posterPath'];
    final imageUrl = posterPath != null && posterPath != 'null'
        ? 'https://image.tmdb.org/t/p/w200$posterPath'
        : '';
    final title = movie['title'] ?? 'Unknown';
    final releaseDate = movie['releaseDate'] ?? movie['release_date'] ?? 'TBD';

    return InkWell(
      onTap: () => showDialog(
        context: context,
        builder: (context) =>
            MovieDetailsDialog(movieId: int.parse(movie['id'].toString())),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF2B2B2B),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: imageUrl.isNotEmpty
                  ? Image.network(
                      imageUrl,
                      width: 50,
                      height: 75,
                      fit: BoxFit.cover,
                    )
                  : Container(width: 50, height: 75, color: Colors.grey[800]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatDateMDY(releaseDate),
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF444444),
                borderRadius: BorderRadius.circular(6),
              ),
              child: IconButton(
                icon: const Icon(
                  Icons.remove_red_eye,
                  color: Colors.white,
                  size: 18,
                ),
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(8),
                onPressed: () async {
                  final norm = {
                    'id': movie['id'],
                    'title': movie['title'],
                    'release_date':
                        movie['releaseDate'] ?? movie['release_date'],
                    'poster_path': movie['posterPath'] ?? movie['poster_path'],
                  };
                  await showDialog(
                    context: context,
                    builder: (context) => RatingDialog(movieData: norm),
                  );
                  _showLoadingOverlay();
                  try {
                    final updated = await _storageService.getDiary();
                    if (updated.any(
                      (m) => m['id'].toString() == movie['id'].toString(),
                    )) {
                      await _storageService.removeFromWatchlist(
                        movie['id'].toString(),
                      );
                      if (_firebaseService.currentUser != null)
                        await _firebaseService.syncToCloud(
                          watchlist: await _storageService.getWatchlist(),
                          diary: updated,
                          tickets: await _storageService.getTickets(),
                        );
                    }
                    await _loadData();
                  } finally {
                    _hideLoadingOverlay();
                  }
                },
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: IconButton(
                icon: const Icon(
                  Icons.close,
                  color: Colors.redAccent,
                  size: 18,
                ),
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(8),
                onPressed: () => _removeWatchlistItem(movie['id'].toString()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF1A1A1A),
      width: MediaQuery.of(context).size.width,
      child: SafeArea(
        child: DefaultTabController(
          length: 5,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'My Movies',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.refresh, color: Colors.grey),
                          onPressed: _loadData,
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const TabBar(
                isScrollable: false,
                indicatorColor: Color(0xFFE50914),
                labelColor: Colors.white,
                unselectedLabelColor: Colors.grey,
                labelPadding: EdgeInsets.symmetric(horizontal: 2.0),
                labelStyle: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
                tabs: [
                  Tab(text: 'Watchlist'),
                  Tab(text: 'Diary'),
                  Tab(text: 'Plans & Tickets'),
                  Tab(text: 'Friends'),
                  Tab(text: 'Profile'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildWatchlistTab(),
                    _buildDiaryTab(),
                    _buildTicketsTab(),
                    _buildFriendsTab(),
                    ProfileTab(
                      diary: _diary,
                      watchlist: _watchlist,
                      onSignOut: () async {
                        setState(() => _isLoading = true);
                        await _firebaseService.signOut();
                        if (mounted) Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTicketsTab() {
    if (_isLoading)
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFE50914)),
      );

    final upcomingTickets = _tickets
        .where((t) => !_isPast(t['date'], t['time']))
        .toList();
    final pastTickets = _tickets
        .where((t) => _isPast(t['date'], t['time']))
        .toList();
    final upcomingPlans = _plans
        .where((p) => !_isPast(p['date'], p['time']))
        .toList();
    final pastPlans = _plans
        .where((p) => _isPast(p['date'], p['time']))
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Text('🎟️', style: TextStyle(fontSize: 20)),
              SizedBox(width: 8),
              Text(
                'My Tickets',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (upcomingTickets.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text(
                'No upcoming tickets.',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ...upcomingTickets.map((t) => _buildTicketCard(t)),
          if (pastTickets.isNotEmpty)
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                title: const Text(
                  'Archived Tickets',
                  style: TextStyle(
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                iconColor: Colors.grey,
                collapsedIconColor: Colors.grey,
                tilePadding: EdgeInsets.zero,
                children: pastTickets
                    .map(
                      (t) => Opacity(opacity: 0.6, child: _buildTicketCard(t)),
                    )
                    .toList(),
              ),
            ),
          const SizedBox(height: 32),
          const Row(
            children: [
              Text('🍿', style: TextStyle(fontSize: 20)),
              SizedBox(width: 8),
              Text(
                'Movie Night Plans',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (upcomingPlans.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text(
                'No upcoming plans.',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ...upcomingPlans.map((p) => _buildPlanCard(p)),
          if (pastPlans.isNotEmpty)
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                title: const Text(
                  'Archived Plans',
                  style: TextStyle(
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                iconColor: Colors.grey,
                collapsedIconColor: Colors.grey,
                tilePadding: EdgeInsets.zero,
                children: pastPlans
                    .map((p) => Opacity(opacity: 0.6, child: _buildPlanCard(p)))
                    .toList(),
              ),
            ),
          if (_tickets.isEmpty && _plans.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.only(top: 40),
                child: Text(
                  'No tickets or plans yet.',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWatchlistTab() {
    if (_isLoading)
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFE50914)),
      );
    if (_watchlist.isEmpty)
      return const Center(
        child: Text('Watchlist is empty', style: TextStyle(color: Colors.grey)),
      );
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    List<dynamic> upcoming = [];
    List<dynamic> released = [];
    for (var movie in _watchlist) {
      final releaseDate =
          DateTime.tryParse(
            (movie['releaseDate'] ?? movie['release_date'] ?? '').toString(),
          ) ??
          DateTime(2099);
      if (releaseDate.isAfter(today))
        upcoming.add(movie);
      else
        released.add(movie);
    }
    upcoming.sort(
      (a, b) =>
          (DateTime.tryParse(
                    (a['releaseDate'] ?? a['release_date'] ?? '').toString(),
                  ) ??
                  DateTime(2099))
              .compareTo(
                DateTime.tryParse(
                      (b['releaseDate'] ?? b['release_date'] ?? '').toString(),
                    ) ??
                    DateTime(2099),
              ),
    );
    released.sort(
      (a, b) =>
          (DateTime.tryParse(
                    (b['releaseDate'] ?? b['release_date'] ?? '').toString(),
                  ) ??
                  DateTime(1900))
              .compareTo(
                DateTime.tryParse(
                      (a['releaseDate'] ?? a['release_date'] ?? '').toString(),
                    ) ??
                    DateTime(1900),
              ),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (upcoming.isNotEmpty) ...[
            const Text(
              'COMING SOON',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            ...upcoming.map((m) => _buildWatchlistCard(m)),
            const SizedBox(height: 24),
          ],
          if (released.isNotEmpty) ...[
            const Text(
              'AVAILABLE TO WATCH',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            ...released.map((m) => _buildWatchlistCard(m)),
          ],
        ],
      ),
    );
  }

  Widget _buildDiaryTab() {
    if (_isLoading)
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFE50914)),
      );
    if (_diary.isEmpty)
      return const Center(
        child: Text(
          'Diary is empty. Log some movies!',
          style: TextStyle(color: Colors.grey),
        ),
      );
    final grouped = _getGroupedDiary();
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: grouped.keys.length,
      itemBuilder: (context, index) {
        final monthYear = grouped.keys.elementAt(index);
        final movies = grouped[monthYear]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              monthYear,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const Divider(color: Color(0xFF333333), thickness: 1, height: 16),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 0.44,
                crossAxisSpacing: 12,
                mainAxisSpacing: 16,
              ),
              itemCount: movies.length,
              itemBuilder: (context, gridIndex) {
                final movie = movies[gridIndex];
                final posterPath = movie['posterPath'];
                final imageUrl = posterPath != null && posterPath != 'null'
                    ? 'https://image.tmdb.org/t/p/w200$posterPath'
                    : '';
                final rating = movie['rating']?.toString() ?? '0.0';
                final displayRating = rating.contains('.')
                    ? rating
                    : '$rating.0';
                final hasPhoto =
                    movie['userPhoto'] != null &&
                    movie['userPhoto'].toString().isNotEmpty;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: imageUrl.isNotEmpty
                                ? Image.network(imageUrl, fit: BoxFit.cover)
                                : Container(color: Colors.grey[800]),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          movie['title'] ?? 'Unknown',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.star,
                              color: Color(0xFFf5c518),
                              size: 12,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              displayRating,
                              style: const TextStyle(
                                color: Color(0xFFf5c518),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            GestureDetector(
                              onTap: () => showDialog(
                                context: context,
                                builder: (context) => RatingDialog(
                                  movieData: {
                                    'id': movie['id'],
                                    'title': movie['title'],
                                    'release_date': movie['releaseDate'],
                                    'poster_path': movie['posterPath'],
                                  },
                                ),
                              ).then((_) => _loadData()),
                              child: const Row(
                                children: [
                                  Text('✏️', style: TextStyle(fontSize: 10)),
                                  SizedBox(width: 2),
                                  Text(
                                    'Edit',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            GestureDetector(
                              onTap: () => showDialog(
                                context: context,
                                builder: (context) =>
                                    SharePreviewDialog(diaryEntry: movie),
                              ),
                              child: const Row(
                                children: [
                                  Icon(
                                    Icons.ios_share,
                                    color: Colors.white,
                                    size: 12,
                                  ),
                                  SizedBox(width: 2),
                                  Text(
                                    'Share',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        if (hasPhoto)
                          InkWell(
                            onTap: () => _viewMemoryPhoto(
                              movie['title'],
                              movie['userPhoto'],
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF222222),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: const Color(0xFF444444),
                                ),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text('📸', style: TextStyle(fontSize: 12)),
                                  SizedBox(width: 4),
                                  Text(
                                    'View',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    Positioned(
                      top: -6,
                      right: -6,
                      child: GestureDetector(
                        onTap: () => _removeDiaryItem(movie['id'].toString()),
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Color(0xFFE50914),
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(4),
                          child: const Icon(
                            Icons.close,
                            size: 12,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }

  Widget _buildFriendsTab() {
    if (_isLoading)
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFE50914)),
      );
    if (_firebaseService.currentUser == null)
      return const Center(
        child: Text(
          'Sign in to view friends',
          style: TextStyle(color: Colors.grey),
        ),
      );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1a1a2e), Color(0xFF16213e)],
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF3a3a5c)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'YOUR FRIEND CODE',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _myFriendCode,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Courier',
                          letterSpacing: 3,
                        ),
                      ),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE50914),
                      ),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _myFriendCode));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Friend code copied! 📋'),
                          ),
                        );
                      },
                      child: const Text(
                        'Copy',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Share this code with friends so they can follow you.',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'FOLLOW SOMEONE',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _friendCodeController,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'Courier',
                    letterSpacing: 2,
                  ),
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    hintText: 'ENTER FILM-XXXXXX',
                    hintStyle: const TextStyle(
                      color: Colors.grey,
                      letterSpacing: 0,
                    ),
                    filled: true,
                    fillColor: const Color(0xFF2B2B2B),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE50914),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () async {
                  if (_friendCodeController.text.trim().isEmpty) return;
                  _showLoadingOverlay();
                  try {
                    final error = await _firebaseService.addFriendByCode(
                      _friendCodeController.text.trim(),
                    );
                    if (error != null) {
                      if (mounted)
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(error),
                            backgroundColor: Colors.red,
                          ),
                        );
                    } else {
                      _friendCodeController.clear();
                      if (mounted)
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Friend added! 🎬'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      await _loadData();
                    }
                  } finally {
                    _hideLoadingOverlay();
                  }
                },
                child: const Text(
                  '+ Add',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'FOLLOWING (${_friendsList.length})',
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          if (_friendsList.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: Text(
                  'No one followed yet.\nAdd a friend above to see their diary!',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
          ..._friendsList.map((f) {
            final avatar = f['photoURL'] ?? '';
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF2B2B2B),
                borderRadius: BorderRadius.circular(10),
              ),
              child: ListTile(
                onTap: () => showDialog(
                  context: context,
                  builder: (context) => FriendProfileDialog(friend: f),
                ),
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFF444444),
                  backgroundImage: avatar.isNotEmpty
                      ? NetworkImage(avatar)
                      : null,
                  child: avatar.isEmpty
                      ? const Text('🎬', style: TextStyle(fontSize: 20))
                      : null,
                ),
                title: Text(
                  f['displayName'] ?? 'Friend',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: const Text(
                  'Tap to view their diary →',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey, size: 20),
                  onPressed: () async {
                    _showLoadingOverlay();
                    try {
                      await _firebaseService.removeFriend(f['uid']);
                      await _loadData();
                    } finally {
                      _hideLoadingOverlay();
                    }
                  },
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

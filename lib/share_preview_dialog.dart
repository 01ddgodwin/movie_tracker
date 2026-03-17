import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'firebase_service.dart';
import 'storage_service.dart';

class SharePreviewDialog extends StatefulWidget {
  final Map<String, dynamic> diaryEntry;
  const SharePreviewDialog({super.key, required this.diaryEntry});

  @override
  State<SharePreviewDialog> createState() => _SharePreviewDialogState();
}

class _SharePreviewDialogState extends State<SharePreviewDialog> {
  final FirebaseService _firebaseService = FirebaseService();
  final StorageService _storageService = StorageService();
  final GlobalKey _captureKey = GlobalKey();
  
  bool _isSharing = false;
  String _section = 'VIP';
  String _seat = '01';

  @override
  void initState() {
    super.initState();
    _checkForSavedTicket();
  }

  // Safely scans saved tickets and splits letters from numbers without crashing
  Future<void> _checkForSavedTicket() async {
    try {
      final tickets = await _storageService.getTickets();
      // Using the exact title match that we know worked perfectly the first time!
      final targetTitle = (widget.diaryEntry['title'] ?? '').toString().toLowerCase().trim();

      for (var t in tickets) {
        final ticketTitle = (t['movie'] ?? t['title'] ?? '').toString().toLowerCase().trim();
        
        if (ticketTitle.isNotEmpty && ticketTitle == targetTitle) {
          final seatsStr = (t['seats'] ?? '').toString().trim();
          
          if (seatsStr.isNotEmpty) {
            // Extract the first grouping of letters (e.g., "F" from "F7,F8")
            final letterMatch = RegExp(r'[A-Za-z]+').firstMatch(seatsStr);
            String parsedSection = letterMatch != null ? letterMatch.group(0)!.toUpperCase() : 'SEC';
            
            // Extract ALL number groupings (e.g., "7" and "8" from "F7,F8")
            final numberMatches = RegExp(r'\d+').allMatches(seatsStr);
            List<String> parsedSeats = numberMatches.map((m) => m.group(0)!).toList();
            
            // If it finds numbers, join them (7,8). If not, just use the raw text as a fallback.
            String parsedSeatStr = parsedSeats.isNotEmpty ? parsedSeats.join(',') : seatsStr.replaceAll(RegExp(r'[A-Za-z\s]+'), '');
            if (parsedSeatStr.isEmpty) parsedSeatStr = '01';

            // Safety limits to prevent breaking the aesthetic ticket UI
            if (parsedSection.length > 4) parsedSection = parsedSection.substring(0, 4);
            if (parsedSeatStr.length > 12) parsedSeatStr = '${parsedSeatStr.substring(0, 10)}..';

            if (mounted) {
              setState(() {
                _section = parsedSection;
                _seat = parsedSeatStr;
              });
            }
            break; // Stop looking once we find the match
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading ticket data for preview: $e');
    }
  }

  Future<void> _shareImage() async {
    setState(() => _isSharing = true);
    try {
      RenderRepaintBoundary boundary = _captureKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      // pixelRatio 3.0 ensures high-res export
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData != null) {
        final directory = await getTemporaryDirectory();
        final imagePath = await File('${directory.path}/share_${DateTime.now().millisecondsSinceEpoch}.png').create();
        await imagePath.writeAsBytes(byteData.buffer.asUint8List());

        await Share.shareXFiles(
          [XFile(imagePath.path)],
          text: 'Check out my rating for ${widget.diaryEntry['title']}! 🍿',
        );
      }
    } catch (e) {
      debugPrint('Error sharing image: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to generate image.', style: TextStyle(color: Colors.white))));
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  Widget _buildTicketDetail(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 1)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'Courier')),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final posterPath = widget.diaryEntry['posterPath'];
    final imageUrl = posterPath != null && posterPath != 'null' ? 'https://image.tmdb.org/t/p/w500$posterPath' : '';
    final title = widget.diaryEntry['title'] ?? 'Unknown Movie';
    final rating = double.tryParse(widget.diaryEntry['rating']?.toString() ?? '0') ?? 0.0;
    
    DateTime watchedDate = DateTime.now();
    try {
      if (widget.diaryEntry['watchedDate'] != null) {
        watchedDate = DateTime.parse(widget.diaryEntry['watchedDate'].toString());
      }
    } catch (_) {}

    final user = _firebaseService.currentUser;
    final firstName = user?.displayName?.split(' ')[0] ?? 'I';

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // --- OUTER WRAPPER ---
          Container(
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(color: const Color(0xFFE50914).withValues(alpha: 0.15), blurRadius: 30, offset: const Offset(0, 10))
              ]
            ),
            // --- THE CAPTURE BOUNDARY ---
            child: RepaintBoundary(
              key: _captureKey,
              child: Container(
                color: const Color(0xFF121212),
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // App Branding Header
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                         Text('🍿', style: TextStyle(fontSize: 14)),
                         SizedBox(width: 8),
                         Text('MOVIE TRACKER', style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2.5)),
                      ]
                    ),
                    const SizedBox(height: 24),

                    // Large High-Res Poster
                    Container(
                      decoration: BoxDecoration(
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 15, offset: const Offset(0, 8))]
                      ),
                      child: imageUrl.isNotEmpty
                          ? Image.network(imageUrl, width: 160, height: 240, fit: BoxFit.cover)
                          : Container(width: 160, height: 240, color: Colors.grey[800]),
                    ),
                    const SizedBox(height: 20),

                    // Movie Title
                    Text(
                      title,
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),

                    // Static Star Rating
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (index) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4.0),
                          child: Icon(
                            index < rating ? Icons.star : Icons.star_border,
                            color: index < rating ? const Color(0xFFF5C518) : Colors.grey[800],
                            size: 32,
                          ),
                        );
                      }),
                    ),
                    
                    const SizedBox(height: 28),

                    // --- TICKET STUB / BARCODE FOOTER ---
                    Row(
                      children: [
                        const Icon(Icons.content_cut, color: Colors.grey, size: 14),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Row(
                            children: List.generate(35, (index) => Expanded(
                              child: Container(
                                margin: const EdgeInsets.symmetric(horizontal: 2),
                                height: 1,
                                color: index % 2 == 0 ? Colors.grey[800] : Colors.transparent,
                              ),
                            )),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('ADMIT ONE // VIP ACCESS', style: TextStyle(color: Color(0xFFE50914), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2)),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                _buildTicketDetail('DATE', DateFormat('MM/dd/yy').format(watchedDate)),
                                const SizedBox(width: 16),
                                // DYNAMIC SECTION & SEAT
                                _buildTicketDetail('SEC', _section),
                                const SizedBox(width: 16),
                                _buildTicketDetail('SEAT', _seat),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 8,
                                  backgroundImage: user?.photoURL != null ? NetworkImage(user!.photoURL!) : null,
                                  backgroundColor: Colors.grey[800],
                                  child: user?.photoURL == null ? const Icon(Icons.person, size: 10, color: Colors.white) : null,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  firstName.toUpperCase(),
                                  style: const TextStyle(color: Colors.grey, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1),
                                ),
                              ],
                            ),
                          ],
                        ),
                        
                        // Aesthetic Digital Barcode & Serial Number
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [2.0, 4.0, 1.0, 3.0, 2.0, 1.0, 5.0, 2.0, 1.0, 3.0, 2.0, 4.0, 1.0].map((w) => Container(
                                margin: const EdgeInsets.only(left: 2),
                                width: w,
                                height: 32,
                                color: Colors.white70,
                              )).toList(),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'TCK-${watchedDate.millisecondsSinceEpoch.toString().substring(5, 13)}',
                              style: const TextStyle(color: Colors.grey, fontSize: 8, fontFamily: 'Courier', letterSpacing: 1.5),
                            )
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // --- UI BUTTONS (Outside the screenshot area) ---
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close', style: TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)), 
                  ),
                  onPressed: _isSharing ? null : _shareImage,
                  icon: _isSharing 
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                      : const Icon(Icons.ios_share, size: 20),
                  label: const Text('Share', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
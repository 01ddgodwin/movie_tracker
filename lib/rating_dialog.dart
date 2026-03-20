import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // <-- NEW IMPORT
import 'storage_service.dart';
import 'firebase_service.dart';
import 'social_service.dart';

class RatingDialog extends StatefulWidget {
  final Map<String, dynamic> movieData;
  const RatingDialog({super.key, required this.movieData});

  @override
  State<RatingDialog> createState() => _RatingDialogState();
}

class _RatingDialogState extends State<RatingDialog> {
  final StorageService _storageService = StorageService();
  final FirebaseService _firebaseService = FirebaseService();
  final ImagePicker _picker = ImagePicker();

  double _rating = 0.0;
  DateTime _watchedDate = DateTime.now();
  bool _isSaving = false;
  bool _isEditing = false;
  String? _existingPhoto;

  @override
  void initState() {
    super.initState();
    _loadExistingData();
  }

  Future<void> _loadExistingData() async {
    final diary = await _storageService.getDiary();
    final existingEntry = diary
        .where((m) => m['id'].toString() == widget.movieData['id'].toString())
        .toList();

    if (existingEntry.isNotEmpty) {
      final data = existingEntry.first;
      setState(() {
        _isEditing = true;
        _rating = double.tryParse(data['rating'].toString()) ?? 0.0;
        _existingPhoto = data['userPhoto'];
        try {
          if (data['watchedDate'] != null) {
            _watchedDate = DateTime.parse(data['watchedDate'].toString());
          }
        } catch (_) {}
      });
    }
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _watchedDate,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFFE50914),
            surface: Color(0xFF1A1A1A),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null && picked != _watchedDate) {
      setState(() {
        _watchedDate = picked;
      });
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 600, 
        imageQuality: 50, 
      );

      if (image != null) {
        final bytes = await image.readAsBytes();
        final base64Image = base64Encode(bytes);
        setState(() {
          _existingPhoto = 'data:image/jpeg;base64,$base64Image';
        });
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
    }
  }

  void _removePhoto() {
    setState(() {
      _existingPhoto = null;
    });
  }

  Future<void> _saveRating() async {
    if (_rating == 0.0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a rating!'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final diaryEntry = {
        'id': widget.movieData['id'].toString(),
        'title': widget.movieData['title'],
        'posterPath':
            widget.movieData['poster_path'] ?? widget.movieData['posterPath'],
        'rating': _rating,
        'watchedDate': _watchedDate.toIso8601String(),
        'userPhoto': _existingPhoto ?? '',
        'timestamp': DateTime.now().toIso8601String(),
      };

      await _storageService.addToDiary(diaryEntry);

      if (_firebaseService.currentUser != null) {
        final w = await _storageService.getWatchlist();
        final d = await _storageService.getDiary();
        final t = await _storageService.getTickets();
        await _firebaseService.syncToCloud(watchlist: w, diary: d, tickets: t);

        // --- UPDATED: DIRECT BROADCAST TO SOCIAL FEED ---
        if (!_isEditing) {
          await FirebaseFirestore.instance.collection('social_feed').add({
            'userId': _firebaseService.currentUser?.uid,
            'userName': _firebaseService.currentUser?.displayName ?? 'Movie Fan',
            'userAvatar': _firebaseService.currentUser?.photoURL ?? '', // ADDED AVATAR
            'movieTitle': widget.movieData['title'] ?? 'Unknown Movie',
            'rating': _rating,
            'timestamp': FieldValue.serverTimestamp(),
          });
        }
        // -------------------------------------
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error saving to diary.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildMemoryPhotoThumbnail() {
    if (_existingPhoto == null || _existingPhoto!.isEmpty) {
      return InkWell(
        onTap: _pickImage,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF2B2B2B),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF444444)),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_a_photo, color: Colors.grey, size: 18),
              SizedBox(width: 8),
              Text(
                'Attach Memory Photo',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget imageWidget;
    if (_existingPhoto!.startsWith('http')) {
      imageWidget = Image.network(_existingPhoto!, fit: BoxFit.cover);
    } else if (_existingPhoto!.startsWith('data:image')) {
      final base64Str = _existingPhoto!.split(',').last;
      imageWidget = Image.memory(base64Decode(base64Str), fit: BoxFit.cover);
    } else {
      imageWidget = Image.file(File(_existingPhoto!), fit: BoxFit.cover);
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF444444)),
      ),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: double.infinity,
              height: 140,
              child: imageWidget,
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: _removePhoto,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.9),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.delete, color: Colors.white, size: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final posterPath =
        widget.movieData['poster_path'] ?? widget.movieData['posterPath'];
    final imageUrl = posterPath != null
        ? 'https://image.tmdb.org/t/p/w200$posterPath'
        : '';
    final title = widget.movieData['title'] ?? 'Unknown Movie';

    return Dialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: imageUrl.isNotEmpty
                        ? Image.network(
                            imageUrl,
                            width: 70,
                            height: 105,
                            fit: BoxFit.cover,
                          )
                        : Container(
                            width: 70,
                            height: 105,
                            color: Colors.grey[800],
                          ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isEditing ? 'Edit Diary Entry' : 'Log Movie',
                          style: const TextStyle(
                            color: Color(0xFFE50914),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.grey),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              const Text(
                'TAP TO RATE',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  return GestureDetector(
                    onTap: () => setState(() => _rating = index + 1.0),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: Icon(
                        index < _rating ? Icons.star : Icons.star_border,
                        color: index < _rating
                            ? const Color(0xFFF5C518)
                            : Colors.grey[600],
                        size: 40,
                      ),
                    ),
                  );
                }),
              ),

              const SizedBox(height: 24),

              // --- EDITABLE DATE ROW ---
              InkWell(
                onTap: _selectDate,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2B2B2B),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF444444)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.calendar_today,
                        color: Colors.grey,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Date Watched',
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            DateFormat('MMMM d, yyyy').format(_watchedDate),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      const Icon(Icons.edit, color: Colors.grey, size: 16),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // --- RESTORED MEMORY PHOTO UI ---
              _buildMemoryPhotoThumbnail(),

              const SizedBox(height: 24),

              // --- SAVE BUTTON ---
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE50914),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: _isSaving ? null : _saveRating,
                  child: _isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          _isEditing ? 'Update Entry' : 'Save to Diary',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
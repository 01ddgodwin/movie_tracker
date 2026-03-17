import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'storage_service.dart';
import 'firebase_service.dart';

class SaveTicketDialog extends StatefulWidget {
  final Map<String, dynamic> movie;
  const SaveTicketDialog({super.key, required this.movie});

  @override
  State<SaveTicketDialog> createState() => _SaveTicketDialogState();
}

class _SaveTicketDialogState extends State<SaveTicketDialog> {
  final StorageService _storageService = StorageService();
  final FirebaseService _firebaseService = FirebaseService();

  File? _originalImage;
  File? _croppedQrFile;
  bool _isProcessing = false;
  bool _detected = false;
  bool _isSaving = false;

  final TextEditingController _theaterController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _timeController = TextEditingController();
  final TextEditingController _seatsController = TextEditingController();

  @override
  void dispose() {
    _theaterController.dispose();
    _dateController.dispose();
    _timeController.dispose();
    _seatsController.dispose();
    super.dispose();
  }

  // Native Date Picker
  Future<void> _selectDate() async {
    DateTime initialDate = DateTime.now();
    try {
      initialDate = DateFormat('MMMM d, yyyy').parse(_dateController.text);
    } catch (_) {}

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
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
    if (picked != null) {
      setState(
        () => _dateController.text = DateFormat('MMMM d, yyyy').format(picked),
      );
    }
  }

  // Native Time Picker
  Future<void> _selectTime() async {
    TimeOfDay initialTime = TimeOfDay.now();
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
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
    if (picked != null) {
      setState(() => _timeController.text = picked.format(context));
    }
  }

  Future<void> _pickAndProcessImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 100,
    );
    if (pickedFile == null) return;

    setState(() {
      _originalImage = File(pickedFile.path);
      _isProcessing = true;
    });

    final inputImage = InputImage.fromFilePath(pickedFile.path);
    final barcodeScanner = BarcodeScanner();
    final barcodes = await barcodeScanner.processImage(inputImage);

    if (barcodes.isNotEmpty) {
      await _cropQRCode(pickedFile.path, barcodes.first.boundingBox);
    }
    barcodeScanner.close();

    final textRecognizer = TextRecognizer();
    final RecognizedText recognizedText = await textRecognizer.processImage(
      inputImage,
    );

    _parseAdvancedDetails(recognizedText.text);
    textRecognizer.close();

    setState(() {
      _isProcessing = false;
      _detected = true;
    });
  }

  Future<void> _cropQRCode(String path, Rect boundingBox) async {
    try {
      final Uint8List bytes = await File(path).readAsBytes();
      img.Image? fullImage = img.decodeImage(bytes);
      if (fullImage != null) {
        img.Image cropped = img.copyCrop(
          fullImage,
          x: (boundingBox.left - 20).toInt().clamp(0, fullImage.width),
          y: (boundingBox.top - 20).toInt().clamp(0, fullImage.height),
          width: (boundingBox.width + 40).toInt().clamp(0, fullImage.width),
          height: (boundingBox.height + 40).toInt().clamp(0, fullImage.height),
        );
        final directory = await getTemporaryDirectory();
        final croppedFile = File(
          '${directory.path}/qr_${DateTime.now().millisecondsSinceEpoch}.png',
        );
        await croppedFile.writeAsBytes(img.encodePng(cropped));
        setState(() => _croppedQrFile = croppedFile);
      }
    } catch (e) {
      debugPrint("Cropping error: $e");
    }
  }

  void _parseAdvancedDetails(String text) {
    final lines = text.split('\n').map((l) => l.trim()).toList();
    final cleanText = text.replaceAll(
      RegExp(r'Confirmation\s*#|Confirmation\s*Number', caseSensitive: false),
      '',
    );

    String theater = "";
    String dateStr = "";
    String timeStr = "";
    String seats = "";

    bool isHarkins = text.toLowerCase().contains('harkins');
    bool isCinemark = text.toLowerCase().contains('cinemark');

    // Theater
    if (isCinemark) {
      theater =
          RegExp(
            r'Cinemark\s+[A-Za-z0-9\s]+',
            caseSensitive: false,
          ).firstMatch(text)?.group(0) ??
          "Cinemark";
    } else if (isHarkins) {
      for (var line in lines) {
        if (line.contains('18') ||
            line.contains('16') ||
            line.contains('Fountains')) {
          theater = line.replaceAll(RegExp(r'\.com.*'), '').trim();
          break;
        }
      }
    } else {
      theater =
          RegExp(
            r'(AMC|Regal|Cinema).+?(?=\n|$)',
            caseSensitive: false,
          ).firstMatch(text)?.group(0) ??
          (lines.isNotEmpty ? lines[0] : "");
    }

    // Date
    final longDateRegex = RegExp(
      r'(?:Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday),\s+([A-Z][a-z]+\s+\d{1,2},\s+\d{4})',
      caseSensitive: false,
    );
    final shortDateRegex = RegExp(r'([A-Z]{3})\s+(\d{1,2})');

    if (longDateRegex.hasMatch(text)) {
      dateStr = longDateRegex.firstMatch(text)!.group(1) ?? "";
    } else if (shortDateRegex.hasMatch(text)) {
      var match = shortDateRegex.firstMatch(text)!;
      dateStr = "${match.group(1)} ${match.group(2)}, ${DateTime.now().year}";
    }

    // Time & Seats
    timeStr =
        RegExp(
          r'(\d{1,2}:\d{2}\s?(?:AM|PM|am|pm)?)',
        ).firstMatch(text)?.group(0) ??
        "";
    seats =
        RegExp(
          r'(?:Seats|SEAT)\s*([A-Z][-]?\d+(?:,\s?[A-Z][-]?\d+)*)',
          caseSensitive: false,
        ).firstMatch(cleanText)?.group(1) ??
        "";

    _theaterController.text = theater;
    _dateController.text = dateStr;
    _timeController.text = timeStr;
    _seatsController.text = seats;
  }

  Future<void> _saveTicket() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final newTicket = {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'movieId': widget.movie['id'].toString(),
        'title': widget.movie['title'],
        'posterPath': widget.movie['posterPath'] ?? widget.movie['poster_path'],
        'theater': _theaterController.text,
        'date': _dateController.text,
        'time': _timeController.text,
        'seats': _seatsController.text,
        'qr': _croppedQrFile?.path ?? _originalImage?.path ?? "",
      };
      await _storageService.addTicket(newTicket);
      if (_firebaseService.currentUser != null) {
        final t = await _storageService.getTickets();
        await _firebaseService.syncToCloud(
          watchlist: await _storageService.getWatchlist(),
          diary: await _storageService.getDiary(),
          tickets: t,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Save Ticket",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (!_detected)
              InkWell(
                onTap: _isProcessing ? null : _pickAndProcessImage,
                child: Container(
                  width: double.infinity,
                  height: 160,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2B2B2B),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF444444)),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _isProcessing
                          ? const CircularProgressIndicator(
                              color: Color(0xFFE50914),
                            )
                          : const Icon(
                              Icons.qr_code_scanner,
                              size: 50,
                              color: Colors.grey,
                            ),
                      const SizedBox(height: 12),
                      Text(
                        _isProcessing ? "Analyzing..." : "Upload Screenshot",
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              Container(
                height: 140,
                width: 140,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _croppedQrFile != null
                    ? Image.file(_croppedQrFile!, fit: BoxFit.contain)
                    : const Icon(Icons.qr_code, size: 80, color: Colors.black),
              ),
              const SizedBox(height: 20),
              _buildField("Theater Name", _theaterController),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildField(
                      "Date",
                      _dateController,
                      onTap: _selectDate,
                      isReadOnly: true,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildField(
                      "Time",
                      _timeController,
                      onTap: _selectTime,
                      isReadOnly: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildField("Seats", _seatsController),
              const SizedBox(height: 30),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE50914),
                  minimumSize: const Size(double.infinity, 54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: _isSaving ? null : _saveTicket,
                child: _isSaving
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(color: Colors.white),
                      )
                    : const Text(
                        "Generate Digital Ticket",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildField(
    String label,
    TextEditingController controller, {
    VoidCallback? onTap,
    bool isReadOnly = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.grey,
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          onTap: onTap,
          readOnly: isReadOnly,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFF222222),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            suffixIcon: isReadOnly
                ? const Icon(Icons.arrow_drop_down, color: Colors.grey)
                : null,
          ),
        ),
      ],
    );
  }
}

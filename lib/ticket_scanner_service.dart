import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class TicketScannerService {
  final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  Future<Map<String, String>> scanTicket(String imagePath) async {
    final inputImage = InputImage.fromFilePath(imagePath);
    final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);
    
    String possibleTitle = '';
    String possibleDate = '';
    
    // Very basic parsing logic (mimicking standard ticket layouts)
    // You can refine these regex rules later based on your local theater's tickets
    final dateRegex = RegExp(r'\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]* \d{1,2}\b|\d{1,2}/\d{1,2}/\d{2,4}');
    final timeRegex = RegExp(r'\d{1,2}:\d{2}\s?(AM|PM|am|pm)');

    for (TextBlock block in recognizedText.blocks) {
      for (TextLine line in block.lines) {
        final text = line.text;
        
        // Look for Dates & Times
        if (dateRegex.hasMatch(text) || timeRegex.hasMatch(text)) {
          possibleDate += '$text ';
        } 
        // Guess the title: Usually all caps or the largest text block
        else if (text.toUpperCase() == text && text.length > 3 && possibleTitle.isEmpty) {
          if (!text.contains('ADMIT') && !text.contains('TICKET') && !text.contains('SEAT')) {
            possibleTitle = text;
          }
        }
      }
    }

    return {
      'title': possibleTitle.trim(),
      'date': possibleDate.trim(),
      'rawText': recognizedText.text, // Keeping raw text just in case
    };
  }

  void dispose() {
    _textRecognizer.close();
  }
}
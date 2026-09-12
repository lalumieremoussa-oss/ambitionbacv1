import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:file_picker/file_picker.dart';

class DocumentExtractor {
  static final Map<String, String> _textCache = {};

  // ============================================================
  // 📚 CHARGER UN SEUL FICHIER HTML POUR LA LEÇON (IA)
  // ============================================================
  static Future<String> chargerGuideMethodologique({
    required String matiereId,
    required String leconId,
  }) async {
    final String filePath = 'assets/iac/$matiereId/${leconId}_IA.html';

    if (await _fileExists(filePath)) {
      final String texteExtrait = await _extractHTMLFromAssets(filePath);
      return texteExtrait;
    } else {
      return "";
    }
  }

  static Future<String> chargerTousLesFichiersDeLaLecon({
    required String matiereId,
    required String leconId,
  }) async {
    return chargerGuideMethodologique(matiereId: matiereId, leconId: leconId);
  }

  static Future<bool> _fileExists(String assetPath) async {
    try {
      await rootBundle.load(assetPath);
      return true;
    } catch (e) {
      return false;
    }
  }

  // ❌ Méthode supprimée car inutilisée
  // static Future<String> _extractPDFFromAssets(String assetPath) async { ... }

  static Future<String> _extractHTMLFromAssets(String assetPath) async {
    if (_textCache.containsKey(assetPath)) return _textCache[assetPath]!;
    try {
      final String htmlContent = await rootBundle.loadString(assetPath);
      final String cleanText = _stripHtml(htmlContent);
      _textCache[assetPath] = cleanText;
      return cleanText;
    } catch (e) {
      return "[Erreur HTML: $e]";
    }
  }

  static String _stripHtml(String html) {
    String cleaned = html.replaceAll(RegExp(r'<[^>]*>'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'&nbsp;'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');
    return cleaned.trim();
  }

  static String _cleanExtractedText(String rawText) {
    String cleaned = rawText.replaceAll(RegExp(r'\s+'), ' ');
    if (cleaned.length > 5000) {
      cleaned = cleaned.substring(0, 5000) + "... [Tronqué]";
    }
    return cleaned.trim();
  }

  // 📷 EXTRACTION DEPUIS L'APPAREIL PHOTO
  static Future<String> takePhotoAndExtractText() async {
    final picker = ImagePicker();
    final XFile? photo = await picker.pickImage(source: ImageSource.camera);
    if (photo == null) return "";
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    final inputImage = InputImage.fromFilePath(photo.path);
    final recognizedText = await textRecognizer.processImage(inputImage);
    await textRecognizer.close();
    return _cleanExtractedText(recognizedText.text);
  }

  // 🖼️ EXTRACTION DEPUIS LA GALERIE D'IMAGES
  static Future<String> pickImageFromGalleryAndExtractText() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return "";

    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    final inputImage = InputImage.fromFilePath(image.path);
    final recognizedText = await textRecognizer.processImage(inputImage);
    await textRecognizer.close();
    return _cleanExtractedText(recognizedText.text);
  }

  // 📄 EXTRACTION DEPUIS UN FICHIER PDF
  static Future<String> pickPDFAndExtractText() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result == null) throw Exception("Aucun fichier sélectionné");
    final File pdfFile = File(result.files.single.path!);
    final Uint8List bytes = await pdfFile.readAsBytes();
    final PdfDocument document = PdfDocument(inputBytes: bytes);
    StringBuffer extractedText = StringBuffer();
    for (int i = 0; i < document.pages.count; i++) {
      final text = PdfTextExtractor(document)
          .extractText(startPageIndex: i, endPageIndex: i);
      extractedText.writeln(text);
    }
    document.dispose();
    return _cleanExtractedText(extractedText.toString());
  }

  static void clearCache() => _textCache.clear();
}

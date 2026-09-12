// 📁 lib/services/ocr_service.dart

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OcrService {
  OcrService._();

  static final OcrService _instance = OcrService._();

  static OcrService get instance => _instance;

  final ImagePicker _picker = ImagePicker();

  Future<String?> pickAndExtractText({
    required ImageSource source,
    int imageQuality = 85,
    double maxWidth = 2000.0,
  }) async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: source,
        imageQuality: imageQuality,
        maxWidth: maxWidth,
      );

      if (picked == null) return null;

      final inputImage = InputImage.fromFilePath(picked.path);
      final textRecognizer = TextRecognizer(
        script: TextRecognitionScript.latin,
      );

      final RecognizedText recognizedText =
          await textRecognizer.processImage(inputImage);
      await textRecognizer.close();

      final extracted = recognizedText.text.trim();
      return extracted.isEmpty ? null : extracted;
    } catch (e) {
      // Relancer pour que l'UI puisse gérer l'erreur
      throw Exception('Impossible de lire le texte de cette image : $e');
    }
  }

  static Future<String?> showImageSourceAndExtract(BuildContext context) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _buildSourceSheet(ctx),
    );

    if (source == null) return null;

    try {
      final text = await OcrService.instance.pickAndExtractText(source: source);
      return text;
    } catch (e) {
      // On relance l'exception pour que l'UI la gère
      rethrow;
    }
  }

  static Widget _buildSourceSheet(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFFFF8F0), // ivoire
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 26),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 18),
            decoration: BoxDecoration(
              color: Colors.grey.shade400,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const Text(
            'Importer une photo du sujet',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Color(0xFF202020),
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Le texte de l’image sera ajouté dans le champ du sujet.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: Color(0xFF707070),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _sourceOption(
                  context,
                  icon: Icons.photo_camera_rounded,
                  label: 'Appareil photo',
                  source: ImageSource.camera,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _sourceOption(
                  context,
                  icon: Icons.photo_library_rounded,
                  label: 'Galerie',
                  source: ImageSource.gallery,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _sourceOption(
    BuildContext context, {
    required IconData icon,
    required String label,
    required ImageSource source,
  }) {
    return GestureDetector(
      onTap: () => Navigator.pop(context, source),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: const Color(0xFFFF7900).withOpacity(.12),
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: const Color(0xFFFF7900), size: 26),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF202020),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

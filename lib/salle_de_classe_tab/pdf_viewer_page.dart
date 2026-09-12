// 📁 lib/pdf_viewer_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:no_screenshot/no_screenshot.dart';

class PdfViewerPage extends StatefulWidget {
  final String pdfPath;
  final String title;

  const PdfViewerPage({
    super.key,
    required this.pdfPath,
    required this.title,
  });

  @override
  State<PdfViewerPage> createState() => _PdfViewerPageState();
}

class _PdfViewerPageState extends State<PdfViewerPage> {
  final PdfViewerController _pdfController = PdfViewerController();
  late final NoScreenshot _noScreenshot;

  @override
  void initState() {
    super.initState();

    // Blocage de la rotation
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    _noScreenshot = NoScreenshot.instance;
    _noScreenshot.screenshotOff();
  }

  @override
  void dispose() {
    _noScreenshot.screenshotOn();
    _pdfController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFFF8C00),
        centerTitle: true,
        elevation: 3,
        title: Text(
          widget.title,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(2.0),
                child: Image.asset(
                  'assets/images/outils/logo_ambitionbac.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          )
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Fond logo en filigrane
          Opacity(
            opacity: 0.2,
            child: Center(
              child: Image.asset(
                'assets/images/outils/logo_ambitionbac.png',
                width: MediaQuery.of(context).size.width * 0.7,
                fit: BoxFit.contain,
              ),
            ),
          ),
          // Lecteur PDF
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: SfPdfViewer.asset(
              widget.pdfPath,
              controller: _pdfController,
              enableDoubleTapZooming: true,
              canShowScrollHead: true,
              canShowScrollStatus: true,
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton.small(
            heroTag: 'zoomIn',
            backgroundColor: const Color(0xFFFF8C00),
            onPressed: () {
              _pdfController.zoomLevel = _pdfController.zoomLevel + 0.25;
            },
            child: const Icon(Icons.zoom_in, color: Colors.white),
          ),
          const SizedBox(height: 8),
          FloatingActionButton.small(
            heroTag: 'zoomOut',
            backgroundColor: const Color(0xFFFF8C00),
            onPressed: () {
              _pdfController.zoomLevel =
                  (_pdfController.zoomLevel - 0.25).clamp(1.0, 3.0);
            },
            child: const Icon(Icons.zoom_out, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

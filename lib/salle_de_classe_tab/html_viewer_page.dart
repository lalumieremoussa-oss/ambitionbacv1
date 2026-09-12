
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';


const Color _ivoryCoastOrange = Color(0xFFE97451); 
const Color _ivoryCoastGreen = Color(0xFF009C4A); 
const Color _courseBackground = Color(0xFFFCFCFC); 
const Color _lightGreenBackground = Color(0xFFE6F5ED); 
const Color _lightOrangeBackground = Color(0xFFFEF0E9); 

class HtmlViewerPage extends StatefulWidget { 
  
  final String htmlPath; 
  final String title; 

  const HtmlViewerPage({
    super.key,
    required this.htmlPath,
    required this.title,
  });

  @override
  State<HtmlViewerPage> createState() => _HtmlViewerPageState();
}

class _HtmlViewerPageState extends State<HtmlViewerPage> {
  String? _htmlContent;
  bool _isLoading = true;


  final Color _headerColor = _ivoryCoastGreen; 
  final Color _titleColor = _ivoryCoastGreen; 
  final Color _remarqueColor = _ivoryCoastOrange; 
  final Color _tableHeaderColor = _lightOrangeBackground; 

  @override
  void initState() {
    super.initState();
    _loadCourseContent();
  
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }
  
  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadCourseContent() async {
    try {
    
      final String fileString =
          await DefaultAssetBundle.of(context).loadString(widget.htmlPath);
      setState(() {
        _htmlContent = fileString;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Erreur de chargement du cours ${widget.htmlPath}: $e');
      setState(() {
        _htmlContent = null;
        _isLoading = false;
      });
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ---------------- APPBAR ----------------
      appBar: AppBar(
        backgroundColor: _headerColor,
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
                  'assets/images/outils/logo_ambition.png', 
                  fit: BoxFit.contain,
                ),
              ),
            ),
          )
        ],
      ),

      // ---------------- CONTENU PRINCIPAL (HTML) ----------------
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator(color: _ivoryCoastGreen)); 
    if (_htmlContent == null) {
      return const Center(
        child: Text(
          "Contenu introuvable",
          textAlign: TextAlign.center,
          style: TextStyle(color: _ivoryCoastGreen), 
        ),
      );
    }

    return Container(
      color: _courseBackground,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: HtmlWidget(
          _htmlContent!,
          factoryBuilder: () => _CustomWidgetFactory(this),
          textStyle: const TextStyle(
            fontFamily: 'Arial',
            fontSize: 17,
            height: 1.6,
            color: Colors.black87,
          ),
          renderMode: RenderMode.column,
        ),
      ),
    );
  }
}

class _CustomWidgetFactory extends WidgetFactory {
  final _HtmlViewerPageState state;

  _CustomWidgetFactory(this.state);

  @override
  void parse(BuildMetadata meta) {
    final element = meta.element;
    final classes = element.classes;

    // 1. TITRE DE LEÇON (titre-lecon)
    if (classes.contains('titre-lecon')) {
      meta.register(BuildOp(
        onRenderBlock: (tree, placeholder) {
          return WidgetPlaceholder(builder: (context, child) {
            return Container(
              alignment: Alignment.center,
              margin: const EdgeInsets.only(bottom: 20, top: 10),
              padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [state._titleColor, _ivoryCoastGreen.withOpacity(0.85)], 
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: state._titleColor.withOpacity(0.5), 
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Text(
                element.text.trim().toUpperCase(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
            );
          });
        },
      ));
    }
    // 2. SOUS-TITRE 
    else if (classes.contains('sous-titre')) {
      meta.register(BuildOp(
        onRenderBlock: (tree, placeholder) {
          return WidgetPlaceholder(builder: (context, child) {
            return Container(
              margin: const EdgeInsets.only(top: 20, bottom: 8),
              padding: const EdgeInsets.only(left: 10, top: 5, bottom: 5),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: _ivoryCoastOrange, width: 4), 
                ),
                color: Colors.white,
              ),
              child: Text(
                element.text.trim(),
                style: TextStyle(
                  color: _ivoryCoastOrange, 
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            );
          });
        },
      ));
    }
    // 3. TITRE DE PARAGRAPHE
    else if (classes.contains('titre-paragraphe') || element.localName == 'sub-titre') {
      meta.register(BuildOp(
        onRenderBlock: (tree, placeholder) {
          return WidgetPlaceholder(builder: (context, child) {
            return Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 5),
              child: Text(
                element.text.trim(),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  decoration: TextDecoration.underline,
                  decorationColor: Colors.black54,
                  decorationThickness: 1.5,
                ),
              ),
            );
          });
        },
      ));
    }
    // 4. REMARQUE 
    else if (classes.contains('remarque')) {
      meta.register(BuildOp(
        onRenderBlock: (tree, placeholder) {
          return WidgetPlaceholder(builder: (context, child) {
            return Container(
              margin: const EdgeInsets.symmetric(vertical: 15),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _lightGreenBackground, 
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: state._remarqueColor.withOpacity(0.5), width: 1),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lightbulb_outline, color: state._remarqueColor, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      element.text.trim(),
                      style: TextStyle(
                        color: state._remarqueColor, 
                        fontWeight: FontWeight.w600,
                        fontStyle: FontStyle.italic,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ],
              ),
            );
          });
        },
      ));
    }
    // 5. GESTION DU TEXTE SOULIGNÉ 
    else if (classes.contains('souligne')) {
      meta.register(BuildOp(
        defaultStyles: (_) => {'font-weight': 'bold', 'text-decoration': 'underline', 'color': '#E97451'}, 
      ));
    }
    
    // 6. GESTION DES HEADERS DE TABLE (th)
    else if (element.localName == 'th') {
      meta.register(BuildOp(
        onRenderBlock: (tree, placeholder) {
            return WidgetPlaceholder(builder: (context, child) {
              return Container(
                color: state._tableHeaderColor, 
                padding: const EdgeInsets.all(8),
                alignment: Alignment.center,
                child: DefaultTextStyle.merge( 
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
                  child: child,
                ),
              );
            });
        }
      ));
    }

    super.parse(meta);
  }

  // 7. GESTION DES IMAGES LOCALES 
  @override
  Widget? buildImage(BuildMetadata meta, ImageMetadata data) {
    final String? url = data.sources.isNotEmpty ? data.sources.first.url : null;

    if (url != null && url.startsWith('assets/')) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10.0),
        child: Builder(builder: (context) {
          return Image.asset(
            url,
            alignment: Alignment.center,
            width: MediaQuery.of(context).size.width * 0.9,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) =>
                const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
          );
        }),
      );
    }
    return super.buildImage(meta, data);
  }
}

// 📁 lib/tabs/cours_entrainement_tab.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../accueil/app_shared.dart';
import 'pdf_viewer_page.dart';
import 'html_viewer_page.dart';
import 'quiz_page.dart';
import '../login/vip_page.dart';
import 'exercices_page.dart';
import 'video_player_screen.dart';

enum _CoursView { matieres, lecons, sections }

class CoursEntrainementTab extends StatefulWidget {
  final TabUpdateCallback onUpdate;
  final String serie;
  final String? lv2;
  final bool isPremium;

  const CoursEntrainementTab({
    super.key,
    required this.onUpdate,
    required this.serie,
    required this.lv2,
    required this.isPremium,
  });

  @override
  State<CoursEntrainementTab> createState() => _CoursEntrainementTabState();
}

class _CoursEntrainementTabState extends State<CoursEntrainementTab> {
  // ---- État de la navigation pédagogique ----
  _CoursView _coursView = _CoursView.matieres;
  List<Map<String, dynamic>> matieres = [];
  List<Map<String, dynamic>> lecons = [];
  Map<String, dynamic>? selectedMatiere;
  Map<String, dynamic>? selectedLecon;
  List<Map<String, dynamic>> sections = [];
  bool _loadingMatieres = true;

  static const Map<String, Map<String, dynamic>> _matiereData = {
    'FR': {
      'title': 'FRANÇAIS',
      'icon': 'assets/images/outils/francais.png',
      'series': ['A', 'C', 'D']
    },
    'PH': {
      'title': 'PHILOSOPHIE',
      'icon': 'assets/images/outils/philosophie.png',
      'series': ['A', 'C', 'D']
    },
    'HI': {
      'title': 'HISTOIRE',
      'icon': 'assets/images/outils/histoire.png',
      'series': ['A', 'C', 'D']
    },
    'GE': {
      'title': 'GÉOGRAPHIE',
      'icon': 'assets/images/outils/geographie.png',
      'series': ['A', 'C', 'D']
    },
    'AN': {
      'title': 'ANGLAIS',
      'icon': 'assets/images/outils/anglais.png',
      'series': ['A', 'C', 'D']
    },
    'PHYS': {
      'title': 'PHYSIQUE',
      'icon': 'assets/images/outils/physique.png',
      'series': ['C', 'D']
    },
    'CHIM': {
      'title': 'CHIMIE',
      'icon': 'assets/images/outils/chimie.png',
      'series': ['C', 'D']
    },
    'SVT': {
      'title': 'SVT',
      'icon': 'assets/images/outils/svt.png',
      'series': ['C', 'D']
    },
    'EPS': {
      'title': 'EPS',
      'icon': 'assets/images/outils/eps.png',
      'series': ['A', 'C', 'D']
    },
  };

  static const Map<String, String> _mathsData = {
    'A': 'MA',
    'C': 'MC',
    'D': 'MD'
  };

  @override
  void initState() {
    super.initState();
    _chargerMatieres();
    _reportCurrentState();
  }

  // ---------- Mise à jour de l'AppBar ----------
  void _reportCurrentState() {
    String title;
    VoidCallback? onBack;
    switch (_coursView) {
      case _CoursView.matieres:
        title = 'COURS & ENTRAÎNEMENT';
        onBack = null;
        break;
      case _CoursView.lecons:
        title = selectedMatiere?['fullTitle'] ?? 'Leçons';
        onBack = _retour;
        break;
      case _CoursView.sections:
        title = selectedLecon?['titre'] ?? 'Sections';
        onBack = _retour;
        break;
    }
    widget.onUpdate(title: title, onBack: onBack);
  }

  // ---------- Chargement matières / leçons ----------
  Future<void> _chargerMatieres() async {
    final String currentSerie = widget.serie;
    List<Map<String, dynamic>> base = [];

    _matiereData.forEach((id, data) {
      if ((data['series'] as List).contains(currentSerie)) {
        base.add({
          'id': id,
          'title': data['title'],
          'fullTitle': data['title'],
          'icon': data['icon'],
        });
      }
    });

    final String mathsId = _mathsData[currentSerie] ?? 'MA';
    final String mathsTitle = 'Mathématiques série $currentSerie';
    final mathItem = {
      'id': mathsId,
      'title': mathsTitle,
      'fullTitle': mathsTitle,
      'icon': 'assets/images/outils/mathematiques.png',
    };

    int geoIndex = base.indexWhere((m) => m['id'] == 'GE');
    if (geoIndex >= 0) {
      base.insert(geoIndex + 1, mathItem);
    } else {
      base.add(mathItem);
    }

    if (currentSerie == 'A') {
      final String lv2Title =
          widget.lv2 == 'Espagnol' ? 'Espagnol' : 'Allemand';
      final String lv2Id = widget.lv2 == 'Espagnol' ? 'ES' : 'DE';
      final String lv2Icon = widget.lv2 == 'Espagnol'
          ? 'assets/images/outils/espagnol.png'
          : 'assets/images/outils/allemand.png';

      final lv2Entry = {
        'id': lv2Id,
        'title': lv2Title,
        'fullTitle': lv2Title,
        'icon': lv2Icon,
      };

      int epsIndex = base.indexWhere((m) => m['id'] == 'EPS');
      if (epsIndex >= 0) {
        base.insert(epsIndex, lv2Entry);
      } else {
        base.add(lv2Entry);
      }
    }

    setState(() {
      matieres = base;
      _loadingMatieres = false;
    });
    _reportCurrentState();
  }

  Future<void> _chargerLecons(Map<String, dynamic> matiere) async {
    final String matiereId = matiere['id']?.toString() ?? '';
    selectedMatiere = matiere;
    setState(() => _loadingMatieres = true);

    try {
      if (['AN', 'DE', 'ES'].contains(matiereId)) {
        final String filePath = 'assets/lecons/$matiereId.json';
        final raw = await rootBundle.loadString(filePath);
        final Map<String, dynamic> langData = json.decode(raw);

        final List<Map<String, dynamic>> loadedLecons = [];
        final String langKey = langData.keys.first;
        for (var level in langData[langKey]) {
          final String levelName = level['level'] ?? 'Niveau';
          for (var lecon in level['lessons']) {
            loadedLecons.add({
              'id': lecon['id'] ?? '',
              'titre': '$levelName - ${lecon['titre'] ?? 'Leçon'}',
              'sections': lecon['sections'] ?? [],
            });
          }
        }
        lecons = loadedLecons;
      } else {
        final String filePath = 'assets/lecons/$matiereId.json';
        final raw = await rootBundle.loadString(filePath);
        final List allLecons = json.decode(raw);
        lecons = allLecons.map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (e) {
      debugPrint('Erreur lors du chargement des leçons : $e');
      lecons = [];
    }

    setState(() {
      _coursView = _CoursView.lecons;
      _loadingMatieres = false;
    });
    _reportCurrentState();
  }

  void _afficherSections(Map<String, dynamic> lecon) {
    selectedLecon = lecon;
    final rawSections = lecon['sections'];
    // Plus de filtre IA : les sections IA n'existent plus dans les JSON.
    sections = (rawSections is List)
        ? rawSections.map((e) => Map<String, dynamic>.from(e)).toList()
        : [];

    selectedMatiere ??= matieres.firstWhere(
        (m) => lecon['id']?.toString().startsWith(m['id'].toString()) ?? false,
        orElse: () => {'id': '', 'fullTitle': 'Matière Inconnue'});

    setState(() => _coursView = _CoursView.sections);
    _reportCurrentState();
  }

  void _retour() {
    if (_coursView == _CoursView.sections) {
      setState(() {
        _coursView = _CoursView.lecons;
        selectedLecon = null;
      });
    } else if (_coursView == _CoursView.lecons) {
      setState(() {
        _coursView = _CoursView.matieres;
        selectedMatiere = null;
      });
    }
    _reportCurrentState();
  }

  bool _isLeconLocked(int leconIndex, String matiereId) {
    if (widget.isPremium) return false;
    if (matiereId == 'SUJET') return true;
    if (['PH', 'MD', 'PHYS', 'CHIM', 'HI', 'SVT'].contains(matiereId)) {
      return leconIndex >= 2;
    }
    return leconIndex >= 1;
  }

  void _showMissingFileDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Fichier non trouvé'),
        content: const Text(
            "Le cours n'est pas encore disponible ou le fichier est manquant. Veuillez réessayer plus tard."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  void _showLockedDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Contenu verrouillé'),
        content: const Text(
            'Ce contenu est réservé aux utilisateurs Premium. Veux-tu devenir Premium ?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Non')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kAppOrange),
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const VipPage()));
            },
            child: const Text('Devenir Premium',
                style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  // ---------- Vues ----------
  Widget _viewMatieres() {
    double screenWidth = MediaQuery.of(context).size.width;
    double customAspectRatio = screenWidth > 360 ? 1.1 : 0.9;

    return Stack(children: [
      Positioned.fill(
        child: Opacity(
          opacity: 0.2,
          child: Image.asset(
            'assets/images/outils/logo_ambition.png',
            fit: BoxFit.contain,
            alignment: Alignment.center,
          ),
        ),
      ),
      GridView.builder(
        padding: EdgeInsets.all(MediaQuery.of(context).size.width * 0.05),
        itemCount: matieres.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 20.0,
          mainAxisSpacing: 20.0,
          childAspectRatio: customAspectRatio,
        ),
        itemBuilder: (_, idx) {
          final item = matieres[idx];
          return GestureDetector(
            onTap: () => _chargerLecons(item),
            child: Container(
              decoration: BoxDecoration(
                color: kMatiereGreen,
                borderRadius: BorderRadius.circular(25),
                boxShadow: const [
                  BoxShadow(
                      blurRadius: 10,
                      color: Colors.black26,
                      offset: Offset(0, 5)),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Expanded(
                        flex: 3,
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: (item['icon'] ?? '').toString().isNotEmpty
                              ? Image.asset(item['icon'], fit: BoxFit.contain)
                              : const Icon(Icons.book,
                                  size: 50, color: Colors.white),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Expanded(
                        flex: 2,
                        child: Center(
                          child: Text(
                            item['title'] ?? 'Matière',
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              // Réduction de la taille de police
                              fontSize: constraints.maxWidth * 0.09,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          );
        },
      ),
    ]);
  }

  Widget _viewLecons() {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: lecons.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, idx) {
        final lecon = lecons[idx];
        return ListTile(
          tileColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          leading: CircleAvatar(
            backgroundColor: Colors.orange.shade100,
            child:
                Text('${idx + 1}', style: const TextStyle(color: Colors.black)),
          ),
          title: Text(lecon['titre'] ?? 'Leçon',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          onTap: () => _afficherSections(lecon),
        );
      },
    );
  }

  Widget _viewSections() {
    final int leconIndex =
        selectedLecon != null ? lecons.indexOf(selectedLecon!) : -1;
    final String matiereId = selectedMatiere?['id']?.toString() ?? '';
    final bool isLeconLocked = _isLeconLocked(leconIndex, matiereId);
    const specialMatieres = ['MA', 'MD', 'MC', 'PHYS', 'CHIM'];

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: sections.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, idx) {
        final sec = sections[idx];
        final String secTitle = (sec['titre'] ?? '').toString().toLowerCase();
        final String originalTitle = (sec['titre'] ?? '').toString();
        final String sectionId = sec['id'] ?? '';
        final bool locked = isLeconLocked;

        // Détection des types (sans IA)
        final bool isQuiz = secTitle.contains('quiz');
        final bool isVideo =
            secTitle.contains('vidéo') || secTitle.contains('video');
        final bool isCours = !isQuiz && !isVideo;

        Color backgroundColor;
        Color textColor = Colors.white;
        if (locked) {
          backgroundColor = Colors.grey.shade300;
          textColor = Colors.grey.shade600;
        } else if (isQuiz) {
          backgroundColor = Colors.green.shade600;
        } else if (isVideo) {
          backgroundColor = Colors.white;
          textColor = Colors.green.shade700;
        } else {
          backgroundColor = kAppOrange;
        }

        IconData leadingIcon = isQuiz
            ? Icons.quiz
            : isVideo
                ? Icons.video_library
                : Icons.description;

        return ListTile(
          tileColor: backgroundColor,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          leading: Icon(leadingIcon, color: textColor),
          title: Text(originalTitle,
              style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
          trailing: locked
              ? Icon(Icons.lock, color: textColor.withOpacity(0.7))
              : Icon(Icons.arrow_forward_ios,
                  color: textColor.withOpacity(0.7), size: 16),
          onTap: () async {
            if (locked) {
              _showLockedDialog();
              return;
            }

            final String currentMatiereId = selectedMatiere?['id'] ?? '';

            // 1) Vidéo
            if (isVideo) {
              final String videoUrl =
                  'https://pub-a6d2205920ac4bee9cce64d6ab17bff0.r2.dev/$currentMatiereId/$sectionId.mp4';
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => VideoPlayerScreen(
                      videoUrl: videoUrl, title: originalTitle),
                ),
              );
              return;
            }

            // 2) Quiz
            if (isQuiz) {
              if (specialMatieres.contains(currentMatiereId)) {
                final String htmlFilePath =
                    'assets/quiz/$currentMatiereId/$sectionId.html';
                try {
                  await rootBundle.load(htmlFilePath);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ExercicesPage(
                        htmlPath: htmlFilePath,
                        sectionId: sectionId,
                        matiere: selectedMatiere?['fullTitle'] ??
                            'Cours et exercice',
                      ),
                    ),
                  );
                } catch (e) {
                  _showMissingFileDialog();
                }
              } else {
                final String quizFilePath =
                    'assets/quiz/$currentMatiereId/$sectionId.json';
                try {
                  final String rawQuizData =
                      await rootBundle.loadString(quizFilePath);
                  final Map<String, dynamic> quizDataMap =
                      json.decode(rawQuizData) as Map<String, dynamic>;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => QuizPage(
                        quizData: quizDataMap,
                        sectionId: sectionId,
                        matiere: selectedMatiere?['fullTitle'] ?? '',
                      ),
                    ),
                  );
                } catch (e) {
                  _showMissingFileDialog();
                }
              }
              return;
            }

            // 3) Cours (incluant les exercices pour les langues et les maths)
            if (isCours) {
              final bool isMaths =
                  ['MA', 'MC', 'MD'].contains(currentMatiereId);
              final bool isLangue =
                  ['AN', 'DE', 'ES'].contains(currentMatiereId);
              final String lowerTitle = secTitle;
              final bool isCoursNom = lowerTitle.contains('cours') ||
                  lowerTitle.contains('speak with your ai teacher') ||
                  lowerTitle.contains('mein ki-lehrer') ||
                  lowerTitle.contains('mi profesor ia');

              // --- MATHÉMATIQUES ---
              if (isMaths) {
                if (isCoursNom) {
                  final String htmlFilePath =
                      'assets/cours/$currentMatiereId/$sectionId.html';
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ExercicesPage(
                        htmlPath: htmlFilePath,
                        sectionId: sectionId,
                        matiere: selectedMatiere?['fullTitle'] ??
                            'Cours et exercice',
                      ),
                    ),
                  );
                } else {
                  final String pdfPath =
                      'assets/cours/$currentMatiereId/$sectionId.pdf';
                  try {
                    await rootBundle.load(pdfPath);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PdfViewerPage(
                            pdfPath: pdfPath, title: originalTitle),
                      ),
                    );
                  } catch (e) {
                    _showMissingFileDialog();
                  }
                }
                return;
              }

              // --- LANGUES ---
              if (isLangue) {
                // Comme IA n'existe plus, tous les cours/langues sont traités comme HTML.
                final String htmlPath =
                    'assets/cours/$currentMatiereId/$sectionId.html';
                try {
                  await rootBundle.load(htmlPath);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => HtmlViewerPage(
                          htmlPath: htmlPath, title: originalTitle),
                    ),
                  );
                } catch (e) {
                  _showMissingFileDialog();
                }
                return;
              }

              // --- AUTRES MATIÈRES (FR, PH, HI, GE, SVT, EPS, etc.) ---
              final String pdfPath =
                  'assets/cours/$currentMatiereId/$sectionId.pdf';
              try {
                await rootBundle.load(pdfPath);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        PdfViewerPage(pdfPath: pdfPath, title: originalTitle),
                  ),
                );
              } catch (e) {
                _showMissingFileDialog();
              }
              return;
            }

            // Si aucun type reconnu
            _showMissingFileDialog();
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingMatieres) {
      return const Center(child: CircularProgressIndicator(color: kAppOrange));
    }
    switch (_coursView) {
      case _CoursView.matieres:
        return _viewMatieres();
      case _CoursView.lecons:
        return _viewLecons();
      case _CoursView.sections:
        return _viewSections();
    }
  }
}

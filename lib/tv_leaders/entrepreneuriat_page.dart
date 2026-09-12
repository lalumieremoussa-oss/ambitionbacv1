
// 📁 lib/tv_leaders/entrepreneuriat_page.dart

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../accueil/app_shared.dart';
import '../login/inscription_view.dart';
import 'lecon_content_page.dart';

/// ============================================================================
/// MODÈLE POUR UN CHAPITRE
/// ============================================================================

class Chapter {
  final String id;
  final String titre;
  final List<Lesson> lecons;

  Chapter({
    required this.id,
    required this.titre,
    required this.lecons,
  });

  factory Chapter.fromJson(Map<String, dynamic> json) => Chapter(
        id: json['id'],
        titre: json['titre'],
        lecons: (json['lecons'] as List)
            .map((e) => Lesson.fromJson(e))
            .toList(),
      );
}

/// ============================================================================
/// MODÈLE POUR UNE LEÇON
/// ============================================================================

class Lesson {
  final String id;
  final String titre;

  Lesson({
    required this.id,
    required this.titre,
  });

  factory Lesson.fromJson(Map<String, dynamic> json) => Lesson(
        id: json['id'],
        titre: json['titre'],
      );
}

// ============================================================================
// PAGE PRINCIPALE
// ============================================================================

class EntrepreneuriatPage extends StatefulWidget {
  final TabUpdateCallback onUpdate;

  const EntrepreneuriatPage({
    super.key,
    required this.onUpdate,
  });

  @override
  State<EntrepreneuriatPage> createState() => _EntrepreneuriatPageState();
}

class _EntrepreneuriatPageState extends State<EntrepreneuriatPage> {
  bool _showLeadership = false;
  bool _showEntrepreneuriat = false;

  // Données chargées depuis les fichiers JSON
  List<Chapter> _leadershipChapters = [];
  List<Chapter> _entrepreneuriatChapters = [];

  bool _loading = true;

  @override
  void initState() {
    super.initState();

    _loadData();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onUpdate(
        title: 'ENTREPRENEURIAT',
        onBack: null,
      );
    });
  }

  // ==========================================================================
  // CHARGEMENT DES DONNÉES
  // ==========================================================================

  Future<void> _loadData() async {
    try {
      final leadershipRaw =
          await rootBundle.loadString('assets/leaders/LEAD.json');

      final entrepreneuriatRaw =
          await rootBundle.loadString('assets/leaders/ENTREP.json');

      final leadershipList = json.decode(leadershipRaw) as List;
      final entrepreneuriatList = json.decode(entrepreneuriatRaw) as List;

      if (!mounted) return;

      setState(() {
        _leadershipChapters =
            leadershipList.map((e) => Chapter.fromJson(e)).toList();

        _entrepreneuriatChapters =
            entrepreneuriatList.map((e) => Chapter.fromJson(e)).toList();

        _loading = false;
      });
    } catch (e) {
      debugPrint('Erreur chargement données : $e');

      if (!mounted) return;

      setState(() {
        _loading = false;
      });
    }
  }

  // ==========================================================================
  // NAVIGATION VERS LES LEÇONS D'UN CHAPITRE
  // ==========================================================================

  void _openChapterLessons(
    Chapter chapter,
    String type,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChapterLessonsPage(
          chapter: chapter,
          type: type,
          onUpdate: widget.onUpdate,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          color: kAppOrange,
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: CustomScrollView(
        slivers: [
          // ==================================================================
          // BANDEAU
          // ==================================================================

          SliverToBoxAdapter(
            child: _buildBanner(),
          ),

          // ==================================================================
          // CONTENU PRINCIPAL
          // ==================================================================

          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // --------------------------------------------------------------
                // CARTES LEADERSHIP / ENTREPRENEURIAT
                // --------------------------------------------------------------

                Row(
                  children: [
                    _buildCard(
                      label: 'LEADERSHIP',
                      color: kMatiereGreen,
                      onTap: () {
                        setState(() {
                          _showLeadership = !_showLeadership;
                          _showEntrepreneuriat = false;
                        });

                        if (_showLeadership) {
                          widget.onUpdate(
                            title: 'LEADERSHIP',
                            onBack: null,
                          );
                        } else {
                          widget.onUpdate(
                            title: 'ENTREPRENEURIAT',
                            onBack: null,
                          );
                        }
                      },
                    ),

                    const SizedBox(width: 16),

                    _buildCard(
                      label: 'ENTREPRENEURIAT',
                      color: kAppOrange,
                      onTap: () {
                        setState(() {
                          _showEntrepreneuriat =
                              !_showEntrepreneuriat;
                          _showLeadership = false;
                        });

                        widget.onUpdate(
                          title: 'ENTREPRENEURIAT',
                          onBack: null,
                        );
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // --------------------------------------------------------------
                // LISTE LEADERSHIP
                // --------------------------------------------------------------

                if (_showLeadership)
                  _buildChapterList(
                    _leadershipChapters,
                    'LEAD',
                  ),

                // --------------------------------------------------------------
                // LISTE ENTREPRENEURIAT
                // --------------------------------------------------------------

                if (_showEntrepreneuriat)
                  _buildChapterList(
                    _entrepreneuriatChapters,
                    'ENTREP',
                  ),

                const SizedBox(height: 30),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // BANNIÈRE
  // ==========================================================================

  Widget _buildBanner() {
    final height = MediaQuery.of(context).size.height * 0.45;

    return Container(
      height: height,
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          bottomRight: Radius.circular(80),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/images/outils/home_bg.png',
              fit: BoxFit.cover,
            ),

            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFE97451).withOpacity(0.75),
                    const Color(0xFFE97451).withOpacity(0.75),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),

            const Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 32,
              ),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Esprit de bâtisseur',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        shadows: [
                          Shadow(
                            blurRadius: 8,
                            color: Colors.black26,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: 8),

                    Text(
                      'Tout ne s\'apprend pas à l\'école…\n'
                      'L\'école nous donne les bases, à nous de les utiliser\n'
                      'pour bâtir en nous un esprit de bâtisseur.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        shadows: [
                          Shadow(
                            blurRadius: 6,
                            color: Colors.black26,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================================
  // CARTE
  // ==========================================================================

  Widget _buildCard({
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            vertical: 18,
          ),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================================================
  // LISTE DES CHAPITRES
  // ==========================================================================

  Widget _buildChapterList(
    List<Chapter> chapters,
    String type,
  ) {
    return Container(
      margin: const EdgeInsets.only(
        top: 8,
        bottom: 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: chapters.length,
        separatorBuilder: (_, __) => Divider(
          color: Colors.grey.shade200,
        ),
        itemBuilder: (context, index) {
          final chapter = chapters[index];

          return ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 4,
            ),
            title: Text(
              chapter.titre,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 15,
              ),
            ),
            trailing: const Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: Colors.grey,
            ),
            onTap: () => _openChapterLessons(
              chapter,
              type,
            ),
          );
        },
      ),
    );
  }
}

// ============================================================================
// PAGE : LISTE DES LEÇONS D'UN CHAPITRE
// ============================================================================

class ChapterLessonsPage extends StatelessWidget {
  final Chapter chapter;
  final String type;
  final TabUpdateCallback onUpdate;

  const ChapterLessonsPage({
    super.key,
    required this.chapter,
    required this.type,
    required this.onUpdate,
  });

  // ==========================================================================
  // VÉRIFICATION PREMIUM
  // ==========================================================================

  Future<bool> _checkPremium() async {
    final prefs = await SharedPreferences.getInstance();

    // Même clé Premium utilisée par l'application.
    return prefs.getBool('premium') ?? false;
  }

  // ==========================================================================
  // CLIC SUR UNE LEÇON
  // ==========================================================================

  Future<void> _openLesson(
    BuildContext context,
    Lesson lesson,
  ) async {
    // ========================================================================
    // ÉTAPE 1 : VÉRIFICATION PREMIUM
    // ========================================================================

    final bool isPremium = await _checkPremium();

    if (!context.mounted) return;

    // ========================================================================
    // ÉTAPE 2 : UTILISATEUR GRATUIT
    // ========================================================================

    if (!isPremium) {
      await _showPremiumDialog(context);
      return;
    }

    // ========================================================================
    // ÉTAPE 3 : UTILISATEUR PREMIUM
    //
    // LeconContentPage n'est créé qu'après validation Premium.
    // Le lien/fichier contenu n'est donc PAS chargé pour un utilisateur
    // gratuit.
    // ========================================================================

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LeconContentPage(
          leconId: lesson.id,
          leconTitre: lesson.titre,
          chapterTitre: chapter.titre,
          type: type,
          onUpdate: onUpdate,
        ),
      ),
    );
  }

  // ==========================================================================
  // DIALOGUE PREMIUM
  // ==========================================================================

  Future<void> _showPremiumDialog(
    BuildContext context,
  ) async {
    await showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          child: Container(
            constraints: const BoxConstraints(
              maxWidth: 430,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 30,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // =================================================================
                // HEADER
                // =================================================================

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(
                    24,
                    28,
                    24,
                    25,
                  ),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFFE97451),
                        kAppOrange,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(28),
                      topRight: Radius.circular(28),
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.18),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withOpacity(0.35),
                            width: 1.5,
                          ),
                        ),
                        child: const Icon(
                          Icons.workspace_premium_rounded,
                          color: Colors.white,
                          size: 40,
                        ),
                      ),

                      const SizedBox(height: 15),

                      const Text(
                        'Désolé…',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),

                      const SizedBox(height: 7),

                      Text(
                        'Cette leçon est réservée aux membres Premium.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.94),
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),

                // =================================================================
                // CORPS
                // =================================================================

                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    24,
                    24,
                    24,
                    20,
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Souhaitez-vous devenir Premium pour accéder à cette leçon et à tous les contenus réservés aux membres ?',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF252525),
                          fontSize: 15,
                          height: 1.45,
                          fontWeight: FontWeight.w500,
                        ),
                      ),

                      const SizedBox(height: 20),

                      // -----------------------------------------------------------
                      // AVANTAGE 1
                      // -----------------------------------------------------------

                      _premiumFeature(
                        icon: Icons.menu_book_rounded,
                        text: 'Accès aux cours Premium',
                      ),

                      // -----------------------------------------------------------
                      // AVANTAGE 2
                      // -----------------------------------------------------------

                      _premiumFeature(
                        icon: Icons.video_library_rounded,
                        text: 'Accès aux contenus exclusifs',
                      ),

                      // -----------------------------------------------------------
                      // AVANTAGE 3
                      // -----------------------------------------------------------

                      _premiumFeature(
                        icon: Icons.auto_awesome_rounded,
                        text: 'Profitez pleinement d’Ambition+',
                      ),

                      const SizedBox(height: 18),

                      // =================================================================
                      // BOUTON DEVENIR PREMIUM
                      // =================================================================

                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: () {
                            // Fermer le dialogue
                            Navigator.pop(dialogContext);

                            // Aller vers InscriptionView
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const InscriptionView(),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kAppOrange,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(17),
                            ),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.workspace_premium_rounded,
                                size: 21,
                              ),
                              SizedBox(width: 9),
                              Text(
                                'DEVENIR PREMIUM',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 8),

                      // =================================================================
                      // ANNULER
                      // =================================================================

                      TextButton(
                        onPressed: () {
                          Navigator.pop(dialogContext);
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.grey.shade600,
                        ),
                        child: const Text(
                          'Peut-être plus tard',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ==========================================================================
  // LIGNE AVANTAGE PREMIUM
  // ==========================================================================

  Widget _premiumFeature({
    required IconData icon,
    required String text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 10,
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: kAppOrange.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: kAppOrange,
              size: 20,
            ),
          ),

          const SizedBox(width: 11),

          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF333333),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          Icon(
            Icons.check_circle_rounded,
            color: kMatiereGreen,
            size: 19,
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // BUILD
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      onUpdate(
        title: chapter.titre,
        onBack: () => Navigator.pop(context),
      );
    });

    return Scaffold(
      backgroundColor: Colors.grey.shade100,

      // ========================================================================
      // APP BAR
      // ========================================================================

      appBar: AppBar(
        title: Text(
          chapter.titre,
        ),
        backgroundColor: kAppOrange,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: true,

        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back,
            color: Colors.white,
          ),
          onPressed: () {
            Navigator.pop(context);

            onUpdate(
              title: 'ENTREPRENEURIAT',
              onBack: null,
            );
          },
        ),
      ),

      // ========================================================================
      // LISTE DES LEÇONS
      // ========================================================================

      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: chapter.lecons.length,

        separatorBuilder: (_, __) => const SizedBox(
          height: 8,
        ),

        itemBuilder: (context, index) {
          final lesson = chapter.lecons[index];

          return Card(
            elevation: 2,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 5,
              ),

              // ----------------------------------------------------------------
              // NUMÉRO
              // ----------------------------------------------------------------

              leading: CircleAvatar(
                backgroundColor: kAppOrange.withOpacity(0.2),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: kAppOrange,
                  ),
                ),
              ),

              // ----------------------------------------------------------------
              // TITRE
              // ----------------------------------------------------------------

              title: Text(
                lesson.titre,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),

              // ----------------------------------------------------------------
              // ICÔNE
              // ----------------------------------------------------------------

              trailing: FutureBuilder<bool>(
                future: _checkPremium(),
                builder: (context, snapshot) {
                  // Pendant la vérification
                  if (!snapshot.hasData) {
                    return const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: kAppOrange,
                      ),
                    );
                  }

                  final bool premium = snapshot.data!;

                  if (premium) {
                    return const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 16,
                      color: Colors.grey,
                    );
                  }

                  return Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: kAppOrange.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.lock_outline_rounded,
                      size: 18,
                      color: kAppOrange,
                    ),
                  );
                },
              ),

              // ----------------------------------------------------------------
              // CLIC
              // ----------------------------------------------------------------

              onTap: () => _openLesson(
                context,
                lesson,
              ),
            ),
          );
        },
      ),
    );
  }
}
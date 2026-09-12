// 📁 lib/tabs/ambition_ia_tab.dart

import 'package:flutter/material.dart';
import '../accueil/app_shared.dart';

import '../ia_pages/ia_fr_dissertation.dart';
import '../ia_pages/ia_fr_commentaire.dart';
import '../ia_pages/ia_ph_dissertation.dart';
import '../ia_pages/ia_ph_commentaire.dart';
import '../ia_pages/ia_hi_dissertation.dart';
import '../ia_pages/ia_hi_commentaire.dart';
import '../ia_pages/ia_ge_dissertation.dart';
import '../ia_pages/ia_ge_commentaire.dart';

import '../ia_pages/ia_an_dictionnaire.dart';
import '../ia_pages/ia_an_coach.dart';
import '../ia_pages/ia_an_coach_ecrit.dart';

import '../ia_pages/ia_lv2_dictionnaire.dart';
import '../ia_pages/ia_lv2_coach.dart';
import '../ia_pages/ia_lv2_coach_ecrit.dart';

class AmbitionIaTab extends StatefulWidget {
  final TabUpdateCallback onUpdate;
  final String? lv2;
  final String serie;

  const AmbitionIaTab({
    super.key,
    required this.onUpdate,
    required this.lv2,
    required this.serie,
  });

  @override
  State<AmbitionIaTab> createState() => _AmbitionIaTabState();
}

class _AmbitionIaTabState extends State<AmbitionIaTab> {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onUpdate(
        title: 'MES PROFS IA',
        onBack: null,
      );
    });
  }

  // ============================================================
  // OUVERTURE D'UNE FONCTION IA
  // ============================================================

  void _openIa(String leconId, String matiereTitre) {
    // Les Prof IA de langues proposent deux modes :
    // CONVERSATION ORALE / CONVERSATION ÉCRITE
    if (leconId == 'AN2' || leconId == 'DE2' || leconId == 'ES2') {
      _showCoachChoiceDialog(
        leconId,
        matiereTitre,
      );
      return;
    }

    Widget screen;

    switch (leconId) {
      case 'FR1':
        screen = IaFrDissertationScreen(
          matiereTitre: matiereTitre,
        );
        break;

      case 'FR2':
        screen = IaFrCommentaireScreen(
          matiereTitre: matiereTitre,
        );
        break;

      case 'PH1':
        screen = IaPhDissertationScreen(
          matiereTitre: matiereTitre,
        );
        break;

      case 'PH2':
        screen = IaPhCommentaireScreen(
          matiereTitre: matiereTitre,
        );
        break;

      case 'HI1':
        screen = IaHiDissertationScreen(
          matiereTitre: matiereTitre,
        );
        break;

      case 'HI2':
        screen = IaHiCommentaireScreen(
          matiereTitre: matiereTitre,
        );
        break;

      case 'GE1':
        screen = IaGeDissertationScreen(
          matiereTitre: matiereTitre,
        );
        break;

      case 'GE2':
        screen = IaGeCommentaireScreen(
          matiereTitre: matiereTitre,
        );
        break;

      case 'AN1':
        screen = IaAnDictionnairePage(
          matiereTitre: matiereTitre,
        );
        break;

      case 'DE1':
      case 'ES1':
        screen = IaLv2DictionnaireScreen(
          matiereTitre: matiereTitre,
          lv2Code: leconId.substring(0, 2),
        );
        break;

      default:
        screen = Scaffold(
          appBar: AppBar(
            title: const Text('Page IA inconnue'),
          ),
          body: const Center(
            child: Text(
              'Aucune page IA définie pour cet ID.',
            ),
          ),
        );
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => screen,
      ),
    );
  }

  // ============================================================
  // DIALOGUE CHOIX CONVERSATION
  // ============================================================

  /// Affiche la boîte de dialogue moderne de choix du mode
  /// de conversation avec le Prof IA.
  void _showCoachChoiceDialog(
    String leconId,
    String matiereTitre,
  ) {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      builder: (BuildContext dialogContext) {
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
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                20,
                22,
                20,
                16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ------------------------------------------------
                  // ICÔNE PROF IA
                  // ------------------------------------------------

                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      color: kAppOrange.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      color: kAppOrange,
                      size: 34,
                    ),
                  ),

                  const SizedBox(height: 15),

                  // ------------------------------------------------
                  // TITRE
                  // ------------------------------------------------

                  const Text(
                    'CHOISISSEZ VOTRE MODE',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF202020),
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),

                  const SizedBox(height: 7),

                  Text(
                    matiereTitre,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),

                  const SizedBox(height: 22),

                  // ------------------------------------------------
                  // CONVERSATION ORALE
                  // ------------------------------------------------

                  _coachModeButton(
                    icon: Icons.mic_rounded,
                    title: 'CONVERSATION ORALE',
                    description: 'Parlez directement avec votre Prof IA',
                    color: kAppOrange,
                    onTap: () {
                      Navigator.pop(dialogContext);

                      _navigateToCoach(
                        leconId,
                        matiereTitre,
                        mode: 'oral',
                      );
                    },
                  ),

                  const SizedBox(height: 12),

                  // ------------------------------------------------
                  // CONVERSATION ÉCRITE
                  // ------------------------------------------------

                  _coachModeButton(
                    icon: Icons.chat_bubble_rounded,
                    title: 'CONVERSATION ÉCRITE',
                    description: 'Échangez avec votre Prof IA par messages',
                    color: kMatiereGreen,
                    onTap: () {
                      Navigator.pop(dialogContext);

                      _navigateToCoach(
                        leconId,
                        matiereTitre,
                        mode: 'écrit',
                      );
                    },
                  ),

                  const SizedBox(height: 12),

                  // ------------------------------------------------
                  // ANNULER
                  // ------------------------------------------------

                  TextButton(
                    onPressed: () {
                      Navigator.pop(dialogContext);
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.grey.shade600,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                    ),
                    child: const Text(
                      'Annuler',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // BOUTON MODE DE CONVERSATION
  // ============================================================

  Widget _coachModeButton({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: 15,
            vertical: 15,
          ),
          decoration: BoxDecoration(
            color: color.withOpacity(0.07),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: color.withOpacity(0.22),
              width: 1.2,
            ),
          ),
          child: Row(
            children: [
              // ------------------------------------------------
              // ICÔNE
              // ------------------------------------------------

              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(0.25),
                      blurRadius: 9,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  icon,
                  color: Colors.white,
                  size: 28,
                ),
              ),

              const SizedBox(width: 14),

              // ------------------------------------------------
              // TEXTE
              // ------------------------------------------------

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: color,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.15,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      description,
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 12,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // ------------------------------------------------
              // FLÈCHE
              // ------------------------------------------------

              Icon(
                Icons.arrow_forward_ios_rounded,
                color: color,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // NAVIGATION VERS LE PROF IA
  // ============================================================

  void _navigateToCoach(
    String leconId,
    String matiereTitre, {
    required String mode,
  }) {
    Widget screen;

    // ==========================================================
    // CONVERSATION ORALE
    // ==========================================================

    if (mode == 'oral') {
      switch (leconId) {
        case 'AN2':
          screen = IaAnCoachScreen(
            matiereTitre: matiereTitre,
          );
          break;

        case 'DE2':
        case 'ES2':
          screen = IaLv2CoachScreen(
            matiereTitre: matiereTitre,
            lv2Code: leconId.substring(0, 2),
          );
          break;

        default:
          screen = const Scaffold(
            body: Center(
              child: Text(
                'Conversation orale non disponible',
              ),
            ),
          );
      }
    }

    // ==========================================================
    // CONVERSATION ÉCRITE
    // ==========================================================

    else {
      switch (leconId) {
        case 'AN2':
          screen = IaAnConversationPage(
            matiereTitre: matiereTitre,
          );
          break;

        case 'DE2':
        case 'ES2':
          screen = IaLv2ConversationPage(
            matiereTitre: matiereTitre,
            lv2Code: leconId.substring(0, 2),
          );
          break;

        default:
          screen = const Scaffold(
            body: Center(
              child: Text(
                'Conversation écrite non disponible',
              ),
            ),
          );
      }
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => screen,
      ),
    );
  }

  // ============================================================
  // CARTE MATIÈRE
  // ============================================================

  Widget _matiereCard({
    required String titre,
    required List<
            ({String label, IconData icon, String leconId, String leconTitre})>
        boutons,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 8,
      ),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            blurRadius: 8,
            color: Colors.black12,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ------------------------------------------------------
          // TITRE MATIÈRE
          // ------------------------------------------------------

          Text(
            titre,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: kAppOrange,
            ),
          ),

          const SizedBox(height: 12),

          // ------------------------------------------------------
          // BOUTONS
          // ------------------------------------------------------

          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: boutons.asMap().entries.map((entry) {
              final index = entry.key;
              final b = entry.value;

              final couleur = index == 0 ? kAppOrange : kMatiereGreen;

              return ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: couleur,
                  foregroundColor: Colors.white,
                  elevation: 3,
                  shadowColor: couleur.withOpacity(0.25),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  _openIa(
                    b.leconId,
                    '$titre — ${b.leconTitre}',
                  );
                },
                icon: Icon(
                  b.icon,
                  size: 18,
                ),
                label: Text(
                  b.label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // BANDEAU SUPÉRIEUR
  // ============================================================

  Widget _buildBanner() {
    final height = MediaQuery.of(context).size.height * 0.30;

    return Container(
      height: height,
      width: double.infinity,
      margin: const EdgeInsets.only(
        bottom: 12,
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          bottomRight: Radius.circular(80),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ----------------------------------------------------
            // IMAGE
            // ----------------------------------------------------

            Image.asset(
              'assets/images/outils/ia_bg.png',
              fit: BoxFit.cover,
            ),

            // ----------------------------------------------------
            // FILTRE ORANGE
            // ----------------------------------------------------

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

            // ----------------------------------------------------
            // TEXTE
            // ----------------------------------------------------

            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 24,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'MES PROFS IA',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
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
                      'Emma & Alex',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
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

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final bool showLv2 = widget.serie == 'A' && widget.lv2 != null;

    final String lv2Nom = widget.lv2 ?? 'Allemand';

    final String lv2Id = lv2Nom == 'Espagnol' ? 'ES' : 'DE';

    final List<Widget> cards = [
      // ========================================================
      // FRANÇAIS
      // ========================================================

      _matiereCard(
        titre: 'FRANÇAIS',
        boutons: [
          (
            label: 'Dissertation',
            icon: Icons.edit_note,
            leconId: 'FR1',
            leconTitre: 'Dissertation',
          ),
          (
            label: 'Commentaire',
            icon: Icons.rate_review,
            leconId: 'FR2',
            leconTitre: 'Commentaire',
          ),
        ],
      ),

      // ========================================================
      // PHILOSOPHIE
      // ========================================================

      _matiereCard(
        titre: 'PHILOSOPHIE',
        boutons: [
          (
            label: 'Dissertation',
            icon: Icons.edit_note,
            leconId: 'PH1',
            leconTitre: 'Dissertation',
          ),
          (
            label: 'Commentaire',
            icon: Icons.rate_review,
            leconId: 'PH2',
            leconTitre: 'Commentaire',
          ),
        ],
      ),

      // ========================================================
      // HISTOIRE
      // ========================================================

      _matiereCard(
        titre: 'HISTOIRE',
        boutons: [
          (
            label: 'Dissertation',
            icon: Icons.edit_note,
            leconId: 'HI1',
            leconTitre: 'Dissertation',
          ),
          (
            label: 'Commentaire',
            icon: Icons.rate_review,
            leconId: 'HI2',
            leconTitre: 'Commentaire',
          ),
        ],
      ),

      // ========================================================
      // GÉOGRAPHIE
      // ========================================================

      _matiereCard(
        titre: 'GÉOGRAPHIE',
        boutons: [
          (
            label: 'Dissertation',
            icon: Icons.edit_note,
            leconId: 'GE1',
            leconTitre: 'Dissertation',
          ),
          (
            label: 'Commentaire',
            icon: Icons.rate_review,
            leconId: 'GE2',
            leconTitre: 'Commentaire',
          ),
        ],
      ),

      // ========================================================
      // ANGLAIS
      // ========================================================

      _matiereCard(
        titre: 'ANGLAIS',
        boutons: [
          (
            label: 'Dictionnaire',
            icon: Icons.menu_book,
            leconId: 'AN1',
            leconTitre: 'Dictionnaire',
          ),
          (
            label: 'Prof IA',
            icon: Icons.auto_awesome,
            leconId: 'AN2',
            leconTitre: 'Prof IA',
          ),
        ],
      ),
    ];

    // ==========================================================
    // LANGUE VIVANTE 2
    // ==========================================================

    if (showLv2) {
      cards.add(
        _matiereCard(
          titre: lv2Nom.toUpperCase(),
          boutons: [
            (
              label: 'Dictionnaire',
              icon: Icons.menu_book,
              leconId: '${lv2Id}1',
              leconTitre: 'Dictionnaire',
            ),
            (
              label: 'Prof IA',
              icon: Icons.auto_awesome,
              leconId: '${lv2Id}2',
              leconTitre: 'Prof IA',
            ),
          ],
        ),
      );
    }

    // ==========================================================
    // AFFICHAGE
    // ==========================================================

    return ListView(
      padding: const EdgeInsets.only(
        bottom: 20,
      ),
      children: [
        _buildBanner(),
        ...cards,
      ],
    );
  }
}

// 📁 lib/ia_pages/ia_fr_commentaire.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'ocr_service.dart';
import 'ia_services.dart';
import '../login/inscription_view.dart';

class IaFrCommentaireScreen extends StatefulWidget {
  final String matiereTitre;

  const IaFrCommentaireScreen({
    super.key,
    required this.matiereTitre,
  });

  @override
  State<IaFrCommentaireScreen> createState() => _IaFrCommentaireScreenState();
}

class _IaFrCommentaireScreenState extends State<IaFrCommentaireScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _subjectController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  late AnimationController _animationController;

  Map<String, dynamic>? _result;
  bool _isGenerating = false;
  String? _errorMessage;
  String? _refusMessage;
  bool _isOcrProcessing = false;

  // Clé du prompt stocké dans Supabase (FR2 pour le commentaire)
  static const String _promptKey = 'FR2';

  // ==========================================================
  // IDENTITÉ VISUELLE (spécifique au commentaire français)
  // ==========================================================

  static const Color ivoire = Color(0xFFFFF8F0);

  // Couleur principale (vert)
  static const Color orange = Color(0xFF169B62);
  static const Color orangeDark = Color(0xFF087A4A);

  // Couleur secondaire (orange)
  static const Color vert = Color(0xFFFF7900);
  static const Color vertDark = Color(0xFFE85F00);

  static const Color jaune = Color(0xFFFCD116);
  static const Color texte = Color(0xFF202020);
  static const Color texteSecondaire = Color(0xFF707070);

  // ==========================================================
  // HISTORIQUE HIVE
  // ==========================================================

  static const String _historyBoxName = 'iaHistoryBox';
  static const String _historyType = 'commentaire_fr';

  Future<void> _saveHistory(
      String question, Map<String, dynamic> response) async {
    try {
      final box = await Hive.openBox(_historyBoxName);
      final entry = {
        'question': question,
        'response': jsonEncode(response),
        'timestamp': DateTime.now().toIso8601String(),
        'type': _historyType,
      };
      await box.add(entry);
    } catch (e) {
      debugPrint('Erreur sauvegarde historique : $e');
    }
  }

  Future<List<Map<String, dynamic>>> _loadHistory() async {
    try {
      final box = await Hive.openBox(_historyBoxName);
      final all = box.values.map((e) => Map<String, dynamic>.from(e)).toList();
      return all.where((entry) => entry['type'] == _historyType).toList();
    } catch (e) {
      debugPrint('Erreur chargement historique : $e');
      return [];
    }
  }

  void _showHistoryDialog() async {
    final history = await _loadHistory();
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (_, controller) {
            return Container(
              decoration: BoxDecoration(
                color: ivoire,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(30)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Icon(Icons.history, color: orange),
                        SizedBox(width: 8),
                        Text(
                          'Historique des commentaires',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: texte,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 24),
                  Expanded(
                    child: history.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(20),
                              child: Text(
                                'Aucun commentaire enregistré pour le moment.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: texteSecondaire,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          )
                        : ListView.builder(
                            controller: controller,
                            itemCount: history.length,
                            itemBuilder: (_, index) {
                              final entry = history.reversed.toList()[index];
                              final question = entry['question'] ?? '';
                              final timestamp = entry['timestamp'] ?? '';
                              final date = timestamp.isNotEmpty
                                  ? DateTime.parse(timestamp)
                                  : null;
                              final formattedDate = date != null
                                  ? '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}'
                                  : 'Date inconnue';

                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: orange.withOpacity(0.1),
                                  child: const Icon(
                                    Icons.question_answer,
                                    color: orange,
                                    size: 18,
                                  ),
                                ),
                                title: Text(
                                  question.length > 60
                                      ? '${question.substring(0, 60)}…'
                                      : question,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: texte,
                                  ),
                                ),
                                subtitle: Text(
                                  formattedDate,
                                  style: const TextStyle(
                                    color: texteSecondaire,
                                    fontSize: 11,
                                  ),
                                ),
                                trailing: const Icon(
                                  Icons.chevron_right,
                                  color: texteSecondaire,
                                ),
                                onTap: () {
                                  final responseJson = entry['response'];
                                  if (responseJson != null) {
                                    try {
                                      final decoded = jsonDecode(responseJson)
                                          as Map<String, dynamic>;
                                      Navigator.pop(context);
                                      _restoreFromHistory(decoded, question);
                                    } catch (e) {
                                      _showElegantSnack(
                                        'Erreur lors de l’affichage de l’historique.',
                                        Icons.error_outline,
                                      );
                                    }
                                  }
                                },
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _restoreFromHistory(Map<String, dynamic> decoded, String question) {
    setState(() {
      _subjectController.text = question;
      _subjectController.selection = TextSelection.collapsed(
        offset: _subjectController.text.length,
      );
      _result = decoded;
      _errorMessage = null;
      _refusMessage = null;
      _isGenerating = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 150));
      if (_scrollController.hasClients) {
        await _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
        );
      }
    });

    _showElegantSnack(
      'Analyse restaurée depuis l’historique',
      Icons.history,
    );
  }

  // ==========================================================
  // GESTION DES APPELS (Supabase)
  // ==========================================================
  //
  // IMPORTANT : l'incrément de `iaacces` est géré UNIQUEMENT côté Edge function.
  // Le client Flutter se contente de LIRE cette valeur pour afficher/contrôler
  // la limite d'essai. Il ne doit jamais la modifier lui-même, sinon le
  // compteur serait incrémenté deux fois (une fois par l'Edge, une fois ici).

  Future<String?> _getUserMatricule() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('matricule');
  }

  Future<int> _getRemainingCalls() async {
    final matricule = await _getUserMatricule();
    if (matricule == null || matricule.isEmpty) return -1;

    try {
      final response = await Supabase.instance.client
          .from('utilisateurs_premium')
          .select('iaacces')
          .eq('matricule', matricule)
          .maybeSingle();

      if (response == null) return -1;

      final int iaacces = response['iaacces'] as int? ?? 0;
      return 10 - iaacces;
    } catch (e) {
      debugPrint('Erreur lors de la vérification des appels : $e');
      return -1;
    }
  }

  // ⚠️ Méthode supprimée : _incrementUsage()
  // Elle est désormais inutile car l'incrément est fait par l'Edge function.
  // Si un jour vous avez besoin de réactiver l'incrémentation côté client,
  // décommentez la méthode ci-dessous MAIS désactivez-la côté Edge pour
  // éviter le double comptage.
  //
  // Future<void> _incrementUsage() async {
  //   final matricule = await _getUserMatricule();
  //   if (matricule == null || matricule.isEmpty) return;
  //
  //   try {
  //     final current = await Supabase.instance.client
  //         .from('utilisateurs_premium')
  //         .select('iaacces')
  //         .eq('matricule', matricule)
  //         .maybeSingle();
  //     if (current != null) {
  //       final int old = current['iaacces'] as int? ?? 0;
  //       await Supabase.instance.client
  //           .from('utilisateurs_premium')
  //           .update({'iaacces': old + 1}).eq('matricule', matricule);
  //     }
  //   } catch (e) {
  //     debugPrint('Erreur lors de l\'incrémentation du compteur : $e');
  //   }
  // }

  // ==========================================================
  // DIALOGUE DE LIMITE ATTEINTE
  // ==========================================================

  Future<void> _showLimitDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 22,
            vertical: 24,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: ivoire,
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: orange.withOpacity(.20),
                  blurRadius: 35,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(24, 25, 24, 25),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [orange, orangeDark],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 66,
                          height: 66,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(.18),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withOpacity(.30),
                              width: 1.5,
                            ),
                          ),
                          child: const Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.white,
                            size: 34,
                          ),
                        ),
                        const SizedBox(height: 15),
                        const Text(
                          'Limite d’essai atteinte',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 23,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '10 requêtes déjà utilisées',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withOpacity(.88),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 23, 24, 25),
                    child: Column(
                      children: [
                        const Text(
                          'Vous avez atteint la limite de 10 requêtes pour la version d’essai.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: texte,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Prof IA vous a offert 10 commentaires composés. '
                          'Passez à Premium pour un accès illimité et des fonctionnalités supplémentaires.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            color: texteSecondaire,
                          ),
                        ),
                        const SizedBox(height: 22),
                        _premiumFeature(
                          Icons.auto_awesome_rounded,
                          'Analyses illimitées',
                        ),
                        _premiumFeature(
                          Icons.menu_book_rounded,
                          'Toutes les matières',
                        ),
                        _premiumFeature(
                          Icons.support_agent_rounded,
                          'Priorité et support',
                        ),
                        const SizedBox(height: 22),
                        SizedBox(
                          width: double.infinity,
                          height: 53,
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const InscriptionView(),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: orange,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(17),
                              ),
                            ),
                            child: const Text(
                              'Découvrir Premium',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 9),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                          },
                          child: const Text(
                            'Plus tard',
                            style: TextStyle(
                              color: texteSecondaire,
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
          ),
        );
      },
    );
  }

  Widget _premiumFeature(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 35,
            height: 35,
            decoration: BoxDecoration(
              color: orange.withOpacity(.10),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: orangeDark, size: 19),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: texte,
              ),
            ),
          ),
          const Icon(Icons.check_circle_rounded, color: orange, size: 19),
        ],
      ),
    );
  }

  // ==========================================================
  // OCR
  // ==========================================================

  Future<void> _pickImageForOcr() async {
    if (_isOcrProcessing) return;

    setState(() => _isOcrProcessing = true);

    try {
      final extracted = await OcrService.showImageSourceAndExtract(context);

      if (extracted != null && extracted.isNotEmpty) {
        setState(() {
          final current = _subjectController.text.trim();
          _subjectController.text =
              current.isEmpty ? extracted : '$current\n$extracted';
          _subjectController.selection = TextSelection.collapsed(
            offset: _subjectController.text.length,
          );
        });
        _focusNode.requestFocus();
        _showElegantSnack(
          'Texte importé depuis l’image.',
          Icons.check_circle_outline_rounded,
        );
      } else if (extracted == null) {
        // Annulé par l'utilisateur
      } else {
        _showElegantSnack(
          'Aucun texte lisible n’a été trouvé sur cette image.',
          Icons.image_not_supported_outlined,
        );
      }
    } catch (e) {
      _showElegantSnack(
        'Impossible de lire le texte de cette image.',
        Icons.error_outline,
      );
    } finally {
      if (mounted) setState(() => _isOcrProcessing = false);
    }
  }

  // ==========================================================
  // INIT
  // ==========================================================

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _animationController.dispose();
    super.dispose();
  }

  // ==========================================================
  // ENVOI (avec promptKey)
  // ==========================================================

  Future<void> _submitSubject() async {
    final subject = _subjectController.text.trim();

    if (subject.isEmpty) {
      _showElegantSnack(
        'Écris d’abord le texte à commenter.',
        Icons.edit_note_rounded,
      );
      return;
    }

    if (_isGenerating) return;

    final remaining = await _getRemainingCalls();
    if (remaining == -1) {
      _showElegantSnack(
        'Impossible de vérifier votre statut. Vérifiez votre connexion.',
        Icons.error_outline,
      );
      return;
    }
    if (remaining <= 0) {
      await _showLimitDialog();
      return;
    }

    setState(() {
      _isGenerating = true;
      _errorMessage = null;
      _refusMessage = null;
      _result = null;
    });

    try {
      final response = await IaService().chatCompletion(
        promptKey: _promptKey,
        userPrompt: subject,
        temperature: 0.2,
        maxTokens: 4000,
      );

      if (!mounted) return;

      final cleaned = _cleanJsonResponse(response);
      final decoded = jsonDecode(cleaned) as Map<String, dynamic>;

      if (decoded.containsKey('type_reponse') &&
          decoded['type_reponse'] == 'refus') {
        final message = decoded['message']?.toString() ??
            'Prof IA ne peut pas traiter cette demande.';
        setState(() {
          _refusMessage = message;
          _isGenerating = false;
        });
        return;
      }

      final validationError = _validateCommentaireJson(decoded);
      if (validationError != null) throw FormatException(validationError);

      await _saveHistory(subject, decoded);

      // ⚠️ NE PLUS incrémenter ici : c'est l'Edge function qui gère le compteur.
      // await _incrementUsage();   <-- SUPPRIMÉ

      setState(() {
        _result = decoded;
        _isGenerating = false;
      });

      await Future.delayed(const Duration(milliseconds: 150));
      if (_scrollController.hasClients) {
        await _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isGenerating = false;
        _errorMessage = _friendlyError(e);
      });
    }
  }

  // ==========================================================
  // NETTOYAGE JSON
  // ==========================================================

  String _cleanJsonResponse(String response) {
    String text = response.trim();

    if (text.startsWith('```json')) {
      text = text.substring(7);
    } else if (text.startsWith('```')) {
      text = text.substring(3);
    }

    if (text.endsWith('```')) {
      text = text.substring(0, text.length - 3);
    }

    text = text.trim();

    final firstBrace = text.indexOf('{');
    final lastBrace = text.lastIndexOf('}');

    if (firstBrace >= 0 && lastBrace > firstBrace) {
      text = text.substring(firstBrace, lastBrace + 1);
    }

    return text.trim();
  }

  // ==========================================================
  // VALIDATION JSON (structure commentaire français – inchangée)
  // ==========================================================

  String? _validateCommentaireJson(Map<String, dynamic> json) {
    final requiredTopLevel = [
      'texte',
      'axes_de_lecture',
      'introduction',
      'conclusion',
      'controle',
    ];

    for (final key in requiredTopLevel) {
      if (!json.containsKey(key)) {
        return 'Structure JSON incomplète : $key manquant.';
      }
    }

    final texte = json['texte'] as Map<String, dynamic>?;
    if (texte == null) return 'Le champ "texte" doit être un objet.';
    final requiredTexte = [
      'auteur',
      'oeuvre',
      'genre',
      'contexte',
      'theme_general',
      'idee_principale'
    ];
    for (final key in requiredTexte) {
      if (!texte.containsKey(key)) {
        return 'Le champ "texte.$key" est manquant.';
      }
    }

    final axes = json['axes_de_lecture'] as Map<String, dynamic>?;
    if (axes == null) return 'Le champ "axes_de_lecture" doit être un objet.';
    if (!axes.containsKey('axe_1') ||
        !axes.containsKey('axe_2') ||
        !axes.containsKey('transition')) {
      return 'Les deux axes et la transition sont obligatoires.';
    }

    final axe1 = axes['axe_1'] as Map<String, dynamic>?;
    final axe2 = axes['axe_2'] as Map<String, dynamic>?;
    if (axe1 == null || axe2 == null) return 'Chaque axe doit être un objet.';

    for (final axe in [axe1, axe2]) {
      final sousThemes = axe['sous_themes'] as List?;
      if (sousThemes == null || sousThemes.length != 2) {
        return 'Chaque axe doit contenir exactement 2 sous-thèmes.';
      }
      for (final st in sousThemes) {
        final stMap = st as Map<String, dynamic>?;
        if (stMap == null) return 'Un sous-thème est invalide.';
        final requiredST = [
          'numero',
          'titre',
          'idee',
          'procedes',
          'exemples',
          'interpretation'
        ];
        for (final key in requiredST) {
          if (!stMap.containsKey(key)) {
            return 'Un sous-thème manque le champ "$key".';
          }
        }
        final procedes = stMap['procedes'] as List?;
        if (procedes == null || procedes.isEmpty) {
          return 'Chaque sous-thème doit contenir au moins un procédé.';
        }
        final exemples = stMap['exemples'] as List?;
        if (exemples == null || exemples.isEmpty) {
          return 'Chaque sous-thème doit contenir au moins un exemple.';
        }
      }
    }

    final transition = axes['transition'] as Map<String, dynamic>?;
    if (transition == null) return 'La transition est invalide.';
    if (!transition.containsKey('bilan_axe_1') ||
        !transition.containsKey('lien_vers_axe_2')) {
      return 'La transition doit contenir bilan_axe_1 et lien_vers_axe_2.';
    }

    final intro = json['introduction'] as Map<String, dynamic>?;
    if (intro == null) return 'L\'introduction est invalide.';
    final requiredIntro = [
      'presentation_auteur',
      'presentation_oeuvre',
      'situation_texte',
      'theme',
      'problematique',
      'annonce_axes'
    ];
    for (final key in requiredIntro) {
      if (!intro.containsKey(key))
        return 'L\'introduction manque le champ "$key".';
    }

    final concl = json['conclusion'] as Map<String, dynamic>?;
    if (concl == null) return 'La conclusion est invalide.';
    final requiredConcl = [
      'bilan_axe_1',
      'bilan_axe_2',
      'idee_principale',
      'ouverture'
    ];
    for (final key in requiredConcl) {
      if (!concl.containsKey(key))
        return 'La conclusion manque le champ "$key".';
    }

    final controle = json['controle'] as Map<String, dynamic>?;
    if (controle == null) return 'Le champ "controle" est invalide.';
    if (controle['nombre_axes'] != 2)
      return 'Le controle indique un nombre d\'axes différent de 2.';
    if (controle['sous_themes_axe_1'] != 2 ||
        controle['sous_themes_axe_2'] != 2) {
      return 'Le controle indique un nombre de sous-thèmes incorrect.';
    }
    if (controle['problematique_unique'] != true)
      return 'La problématique doit être unique.';
    if (controle['citations_du_texte'] != true)
      return 'Les citations doivent provenir du texte.';
    if (controle['redaction_complete'] != false)
      return 'La rédaction complète est interdite.';

    return null;
  }

  // ==========================================================
  // ERREURS
  // ==========================================================

  String _friendlyError(Object error) {
    final message = error.toString().toLowerCase();

    if (message.contains('format') ||
        message.contains('json') ||
        message.contains('structure')) {
      return 'Prof IA n’a pas reçu une correction dans le format attendu. Réessaie avec ton texte.';
    }

    if (message.contains('429')) {
      return 'Prof IA reçoit beaucoup de demandes actuellement. Réessaie dans quelques instants.';
    }

    if (message.contains('401')) {
      return 'Le professeur IA rencontre un problème d’autorisation.';
    }

    if (message.contains('timeout') ||
        message.contains('connection') ||
        message.contains('socket')) {
      return 'La connexion avec Prof IA a été interrompue. Vérifie ta connexion puis réessaie.';
    }

    return 'Prof IA n’a pas pu terminer l’analyse. Réessaie dans quelques instants.';
  }

  // ==========================================================
  // SNACKBAR
  // ==========================================================

  void _showElegantSnack(String message, IconData icon) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 18),
        backgroundColor: texte,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(17),
        ),
        content: Row(
          children: [
            Icon(
              icon,
              color: jaune,
              size: 21,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // BUILD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ivoire,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: CustomScrollView(
                controller: _scrollController,
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: _buildHero(),
                  ),
                  SliverToBoxAdapter(
                    child: _buildSubjectComposer(),
                  ),
                  if (_isGenerating)
                    SliverToBoxAdapter(
                      child: _buildThinkingCard(),
                    ),
                  if (_errorMessage != null)
                    SliverToBoxAdapter(
                      child: _buildProfError(),
                    ),
                  if (_refusMessage != null)
                    SliverToBoxAdapter(
                      child: _buildRefusMessage(),
                    ),
                  if (_result != null)
                    SliverToBoxAdapter(
                      child: _buildResult(),
                    ),
                  const SliverToBoxAdapter(
                    child: SizedBox(height: 50),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // TOP BAR
  // ==========================================================

  Widget _buildTopBar() {
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 17),
      decoration: BoxDecoration(
        color: ivoire,
        border: Border(
          bottom: BorderSide(
            color: Colors.black.withOpacity(.05),
          ),
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 43,
              height: 43,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.black.withOpacity(.05),
                ),
              ),
              child: const Icon(
                Icons.arrow_back_rounded,
                color: texte,
              ),
            ),
          ),
          const SizedBox(width: 13),
          Container(
            width: 43,
            height: 43,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  orange,
                  orangeDark,
                ],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'PROF IA',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                    color: texte,
                  ),
                ),
                Text(
                  'Commentaire composé',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: texteSecondaire,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _showHistoryDialog,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: orange.withOpacity(0.15),
                ),
              ),
              child: const Icon(
                Icons.history,
                color: orange,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 7,
            ),
            decoration: BoxDecoration(
              color: orange.withOpacity(.09),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.verified_rounded,
                  size: 15,
                  color: orange,
                ),
                SizedBox(width: 5),
                Text(
                  'PRO',
                  style: TextStyle(
                    color: orangeDark,
                    fontWeight: FontWeight.w800,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // HERO
  // ==========================================================

  Widget _buildHero() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(23, 24, 23, 23),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              Color(0xFF1A8C5C),
              Color(0xFF087A4A),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(29),
          boxShadow: [
            BoxShadow(
              color: orange.withOpacity(.20),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: -25,
              top: -28,
              child: Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(.07),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              right: 32,
              bottom: -55,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(.05),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.school_rounded,
                        color: Colors.white,
                        size: 23,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'ATELIER DE COMMENTAIRE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text(
                  'Analyse le texte.\nConstruis ton commentaire.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    height: 1.08,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.5,
                  ),
                ),
                const SizedBox(height: 13),
                Text(
                  'Prof IA décortique le texte littéraire et te guide pas à pas vers un plan de commentaire composé.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(.90),
                    fontSize: 13.5,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    _heroBadge(
                      Icons.account_tree_rounded,
                      'AXES',
                    ),
                    const SizedBox(width: 8),
                    _heroBadge(
                      Icons.menu_book_rounded,
                      'PROCÉDÉS',
                    ),
                    const SizedBox(width: 8),
                    _heroBadge(
                      Icons.compare_arrows_rounded,
                      'CITATIONS',
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroBadge(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.13),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: Colors.white.withOpacity(.12),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 13,
            color: Colors.white,
          ),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 8.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // COMPOSITEUR (avec OCR)
  // ==========================================================

  Widget _buildSubjectComposer() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(27),
          border: Border.all(
            color: Colors.black.withOpacity(.055),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.045),
              blurRadius: 20,
              offset: const Offset(0, 9),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(19, 19, 19, 15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: orange.withOpacity(.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.edit_document,
                      color: orangeDark,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Le texte à commenter',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: texte,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Colle ou recopie le texte littéraire (poésie, roman, théâtre…).',
                          style: TextStyle(
                            fontSize: 11,
                            color: texteSecondaire,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              Container(
                decoration: BoxDecoration(
                  color: ivoire,
                  borderRadius: BorderRadius.circular(19),
                  border: Border.all(
                    color: orange.withOpacity(.10),
                  ),
                ),
                child: TextField(
                  controller: _subjectController,
                  focusNode: _focusNode,
                  minLines: 5,
                  maxLines: 8,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    color: texte,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: const InputDecoration(
                    hintText:
                        'Exemple :\n« La terre était grise, le blé était gris, le ciel était gris… »',
                    hintStyle: TextStyle(
                      color: Color(0xFFAAA29A),
                      height: 1.45,
                      fontSize: 13.5,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(17),
                  ),
                ),
              ),
              const SizedBox(height: 13),
              Row(
                children: [
                  const Icon(
                    Icons.lightbulb_outline_rounded,
                    color: orange,
                    size: 17,
                  ),
                  const SizedBox(width: 7),
                  const Expanded(
                    child: Text(
                      'Un texte précis donne une analyse plus précise.',
                      style: TextStyle(
                        color: texteSecondaire,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 13),
              Row(
                children: [
                  GestureDetector(
                    onTap: _isOcrProcessing ? null : _pickImageForOcr,
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: orange.withOpacity(.10),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: orange.withOpacity(.15),
                        ),
                      ),
                      child: _isOcrProcessing
                          ? const Padding(
                              padding: EdgeInsets.all(13),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(orangeDark),
                              ),
                            )
                          : const Icon(
                              Icons.camera_alt_rounded,
                              color: orangeDark,
                              size: 21,
                            ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _isOcrProcessing
                          ? 'Lecture du texte de l’image…'
                          : 'Importer une photo du texte',
                      style: const TextStyle(
                        color: texteSecondaire,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: _submitSubject,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 17,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            orange,
                            orangeDark,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: [
                          BoxShadow(
                            color: orange.withOpacity(.20),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.auto_awesome_rounded,
                            color: Colors.white,
                            size: 17,
                          ),
                          SizedBox(width: 7),
                          Text(
                            'Analyser',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // CARTE REFUS
  // ==========================================================

  Widget _buildRefusMessage() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF1EB),
          borderRadius: BorderRadius.circular(25),
          border: Border.all(
            color: orange.withOpacity(.20),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 45,
                  height: 45,
                  decoration: BoxDecoration(
                    color: orange,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(
                    Icons.school_rounded,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Prof IA',
                        style: TextStyle(
                          color: orangeDark,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Message pédagogique',
                        style: TextStyle(
                          color: texteSecondaire,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              _refusMessage ?? '',
              style: const TextStyle(
                color: texte,
                fontSize: 14,
                height: 1.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(.75),
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: orangeDark,
                    size: 18,
                  ),
                  SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Prof IA est spécialisé en commentaire composé. '
                      'Envoie un texte littéraire pour obtenir un plan détaillé.',
                      style: TextStyle(
                        color: texteSecondaire,
                        fontSize: 11.5,
                        height: 1.4,
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
  }

  // ==========================================================
  // AUTRES COMPOSANTS (Thinking, Error, Loading)
  // ==========================================================

  Widget _buildThinkingCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 17, 18, 7),
      child: Container(
        padding: const EdgeInsets.all(19),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(23),
          border: Border.all(
            color: orange.withOpacity(.12),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 47,
              height: 47,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    orange,
                    orangeDark,
                  ],
                ),
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 13),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Prof IA travaille...',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: texte,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Lecture du texte • repérage des procédés • construction des axes',
                    style: TextStyle(
                      fontSize: 10.5,
                      height: 1.35,
                      color: texteSecondaire,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const SizedBox(
              width: 19,
              height: 19,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(
                  orange,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfError() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF1EB),
          borderRadius: BorderRadius.circular(25),
          border: Border.all(
            color: orange.withOpacity(.20),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 45,
                  height: 45,
                  decoration: BoxDecoration(
                    color: orange,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(
                    Icons.school_rounded,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Prof IA',
                        style: TextStyle(
                          color: orangeDark,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Un petit arrêt pédagogique',
                        style: TextStyle(
                          color: texteSecondaire,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage ??
                  'Désolé, je suis là pour t’aider à travailler ton commentaire composé.',
              style: const TextStyle(
                color: texte,
                fontSize: 14,
                height: 1.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(.75),
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: orangeDark,
                    size: 18,
                  ),
                  SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Envoie un texte littéraire (poème, extrait de roman, scène de théâtre…) pour commencer.',
                      style: TextStyle(
                        color: texteSecondaire,
                        fontSize: 11.5,
                        height: 1.4,
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
  }

  // ==========================================================
  // RÉSULTAT (inchangé)
  // ==========================================================

  Widget _buildResult() {
    final result = _result!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildResultHeader(result),
          const SizedBox(height: 16),
          _buildTexteSection(result),
          const SizedBox(height: 15),
          _buildAxesSection(result),
          const SizedBox(height: 15),
          _buildIntroductionSection(result),
          const SizedBox(height: 15),
          _buildConclusionSection(result),
        ],
      ),
    );
  }

  // ==========================================================
  // HEADER RESULTAT
  // ==========================================================

  Widget _buildResultHeader(Map<String, dynamic> result) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TA FEUILLE DE ROUTE',
                style: TextStyle(
                  color: orangeDark,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Plan de commentaire',
                style: TextStyle(
                  color: texte,
                  fontSize: 25,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.4,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 11,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: orange.withOpacity(.09),
            borderRadius: BorderRadius.circular(13),
          ),
          child: const Row(
            children: [
              Icon(
                Icons.check_circle_rounded,
                color: orange,
                size: 15,
              ),
              SizedBox(width: 5),
              Text(
                'ANALYSÉ',
                style: TextStyle(
                  color: orangeDark,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==========================================================
  // SECTION TEXTE
  // ==========================================================

  Widget _buildTexteSection(Map<String, dynamic> result) {
    final textData = Map<String, dynamic>.from(result['texte'] ?? {});
    return _sectionContainer(
      accent: orange,
      icon: Icons.menu_book_rounded,
      label: 'TEXTE',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _infoRow('Auteur', textData['auteur']?.toString() ?? ''),
          const SizedBox(height: 6),
          _infoRow('Œuvre', textData['oeuvre']?.toString() ?? ''),
          const SizedBox(height: 6),
          _infoRow('Genre', textData['genre']?.toString() ?? ''),
          const SizedBox(height: 6),
          _infoRow('Contexte', textData['contexte']?.toString() ?? ''),
          const SizedBox(height: 12),
          _miniLabel('Thème général'),
          const SizedBox(height: 4),
          _textBlock(textData['theme_general']),
          const SizedBox(height: 12),
          _miniLabel('Idée principale'),
          const SizedBox(height: 4),
          _textBlock(textData['idee_principale']),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: const TextStyle(
              color: texteSecondaire,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: texte,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================================
  // SECTION AXES
  // ==========================================================

  Widget _buildAxesSection(Map<String, dynamic> result) {
    final axes = Map<String, dynamic>.from(result['axes_de_lecture'] ?? {});
    final axe1 = Map<String, dynamic>.from(axes['axe_1'] ?? {});
    final axe2 = Map<String, dynamic>.from(axes['axe_2'] ?? {});
    final transition = Map<String, dynamic>.from(axes['transition'] ?? {});

    return _sectionContainer(
      accent: orange,
      icon: Icons.alt_route_rounded,
      label: 'AXES DE LECTURE',
      child: Column(
        children: [
          _buildAxe(
            number: 'I',
            data: axe1,
            color: orange,
          ),
          const SizedBox(height: 14),
          _buildTransitionCard(transition),
          const SizedBox(height: 14),
          _buildAxe(
            number: 'II',
            data: axe2,
            color: vert,
          ),
        ],
      ),
    );
  }

  Widget _buildAxe({
    required String number,
    required Map<String, dynamic> data,
    required Color color,
  }) {
    final sousThemes = (data['sous_themes'] as List?) ?? [];
    final titre = data['titre']?.toString() ?? '';
    final centreInteret = data['centre_interet']?.toString() ?? '';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withOpacity(.13),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.035),
            blurRadius: 17,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withOpacity(.055),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      number,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titre,
                        style: const TextStyle(
                          color: texte,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        centreInteret,
                        style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                for (int i = 0; i < sousThemes.length; i++)
                  _buildSousTheme(
                    data: sousThemes[i] as Map<String, dynamic>,
                    index: i + 1,
                    color: color,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSousTheme({
    required Map<String, dynamic> data,
    required int index,
    required Color color,
  }) {
    final titre = data['titre']?.toString() ?? '';
    final idee = data['idee']?.toString() ?? '';
    final procedes = (data['procedes'] as List?) ?? [];
    final exemples = (data['exemples'] as List?) ?? [];
    final interpretation = data['interpretation']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ivoire,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.black.withOpacity(.045),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '$index',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                titre,
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _miniLabel('Idée'),
          const SizedBox(height: 4),
          Text(
            idee,
            style: const TextStyle(
              color: texte,
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          _miniLabel('Procédés'),
          const SizedBox(height: 4),
          for (var proc in procedes)
            _procItem(proc as Map<String, dynamic>, color),
          const SizedBox(height: 12),
          _miniLabel('Exemples et interprétation'),
          const SizedBox(height: 4),
          for (var ex in exemples)
            _exempleItem(ex as Map<String, dynamic>, color),
          const SizedBox(height: 8),
          Text(
            interpretation,
            style: const TextStyle(
              color: texteSecondaire,
              fontSize: 12.5,
              height: 1.5,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _procItem(Map<String, dynamic> proc, Color color) {
    final nom = proc['nom']?.toString() ?? '';
    final explication = proc['explication']?.toString() ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.arrow_right_rounded,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '$nom : ',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  TextSpan(
                    text: explication,
                    style: const TextStyle(
                      color: texteSecondaire,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _exempleItem(Map<String, dynamic> ex, Color color) {
    final citation = ex['citation']?.toString() ?? '';
    final procede = ex['procede_associe']?.toString() ?? '';
    final effet = ex['effet']?.toString() ?? '';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.black.withOpacity(.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '« $citation »',
            style: const TextStyle(
              color: texte,
              fontSize: 13,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: 'Procédé : ',
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(
                  text: procede,
                  style: const TextStyle(
                    color: texteSecondaire,
                    fontSize: 11,
                  ),
                ),
                const TextSpan(text: '  •  '),
                TextSpan(
                  text: 'Effet : ',
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(
                  text: effet,
                  style: const TextStyle(
                    color: texteSecondaire,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransitionCard(Map<String, dynamic> transition) {
    final bilan = transition['bilan_axe_1']?.toString() ?? '';
    final lien = transition['lien_vers_axe_2']?.toString() ?? '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFCF8E8),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: jaune.withOpacity(.45),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: jaune,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.swap_vert_rounded,
              color: texte,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'TRANSITION',
                  style: TextStyle(
                    color: texte,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                _transitionLine('Bilan axe I', bilan),
                const SizedBox(height: 6),
                _transitionLine('Lien vers axe II', lien),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _transitionLine(String title, String text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: texteSecondaire,
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          text,
          style: const TextStyle(
            color: texte,
            fontSize: 12,
            height: 1.4,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // ==========================================================
  // SECTION INTRODUCTION
  // ==========================================================

  Widget _buildIntroductionSection(Map<String, dynamic> result) {
    final intro = Map<String, dynamic>.from(result['introduction'] ?? {});
    return _sectionContainer(
      accent: vert,
      icon: Icons.play_arrow_rounded,
      label: 'INTRODUCTION GUIDÉE',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _introItem('Présentation de l\'auteur', intro['presentation_auteur']),
          _introItem('Présentation de l\'œuvre', intro['presentation_oeuvre']),
          _introItem('Situation du texte', intro['situation_texte']),
          _introItem('Thème', intro['theme']),
          _introItem('Problématique', intro['problematique']),
          _introItem('Annonce des axes', intro['annonce_axes']),
        ],
      ),
    );
  }

  Widget _introItem(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: vertDark,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: .5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value?.toString() ?? '',
            style: const TextStyle(
              color: texte,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // SECTION CONCLUSION
  // ==========================================================

  Widget _buildConclusionSection(Map<String, dynamic> result) {
    final concl = Map<String, dynamic>.from(result['conclusion'] ?? {});
    return _sectionContainer(
      accent: orange,
      icon: Icons.flag_rounded,
      label: 'CONCLUSION — INDICATIONS',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _conclusionItem('Bilan axe I', concl['bilan_axe_1'], orange),
          const SizedBox(height: 8),
          _conclusionItem('Bilan axe II', concl['bilan_axe_2'], vert),
          const SizedBox(height: 8),
          _conclusionItem('Idée principale', concl['idee_principale'], texte),
          const SizedBox(height: 8),
          _conclusionItem('Ouverture', concl['ouverture'], orange),
        ],
      ),
    );
  }

  Widget _conclusionItem(String label, dynamic value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ivoire,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: color.withOpacity(.10),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: .5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value?.toString() ?? '',
            style: const TextStyle(
              color: texte,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // COMPOSANTS UI GÉNÉRIQUES
  // ==========================================================

  Widget _sectionContainer({
    required Color accent,
    required IconData icon,
    required String label,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        border: Border.all(
          color: accent.withOpacity(.12),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.03),
            blurRadius: 15,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withOpacity(.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  color: accent == jaune ? texte : accent,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 17),
          child,
        ],
      ),
    );
  }

  Widget _miniLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: texteSecondaire,
        fontSize: 8.5,
        fontWeight: FontWeight.w900,
        letterSpacing: 1,
      ),
    );
  }

  Widget _textBlock(dynamic value) {
    return Text(
      value?.toString() ?? '',
      style: const TextStyle(
        color: texte,
        fontSize: 13,
        height: 1.5,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

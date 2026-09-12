// 📁 lib/ia_pages/ia_ph_commentaire.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'ocr_service.dart';
import 'ia_services.dart';
import '../login/inscription_view.dart';

class IaPhCommentaireScreen extends StatefulWidget {
  final String matiereTitre;

  const IaPhCommentaireScreen({
    super.key,
    required this.matiereTitre,
  });

  @override
  State<IaPhCommentaireScreen> createState() => _IaPhCommentaireScreenState();
}

class _IaPhCommentaireScreenState extends State<IaPhCommentaireScreen>
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

  // Clé du prompt stocké dans Supabase (PH2 pour le commentaire philosophique)
  static const String _promptKey = 'PH2';

  // ==========================================================
  // IDENTITÉ VISUELLE (couleurs inversées : vert principal, orange secondaire)
  // ==========================================================

  static const Color ivoire = Color(0xFFFFF8F0);

  static const Color orange = Color(0xFF169B62); // vert
  static const Color orangeDark = Color(0xFF087A4A);
  static const Color vert = Color(0xFFFF7900); // orange
  static const Color vertDark = Color(0xFFE85F00);

  static const Color jaune = Color(0xFFFCD116);
  static const Color texte = Color(0xFF202020);
  static const Color texteSecondaire = Color(0xFF707070);

  // ==========================================================
  // HISTORIQUE HIVE
  // ==========================================================

  static const String _historyBoxName = 'iaHistoryBox';
  static const String _historyType = 'commentaire_ph';

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
                          'Historique des commentaires philosophiques',
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
                                  if (responseJson == null) return;
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
      'Commentaire restauré depuis l’historique',
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
                          'Prof IA vous a offert 10 commentaires philosophiques. '
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
  // OCR – Utilisation du service
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

    // Vérification des appels restants
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

      // Vérification du refus de l'IA
      if (decoded.containsKey('type_reponse') &&
          decoded['type_reponse'] == 'refus') {
        final message = decoded['message']?.toString() ??
            'Prof IA est spécialisé dans les commentaires philosophiques. Envoie un texte à analyser.';
        setState(() {
          _refusMessage = message;
          _isGenerating = false;
        });
        return;
      }

      // Validation de la structure JSON spécifique à la philosophie
      final validationError = _validatePhiloJson(decoded);
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
  // VALIDATION DU JSON (spécifique à la philosophie, inchangée)
  // ==========================================================

  String? _validatePhiloJson(Map<String, dynamic> json) {
    final requiredTopLevel = [
      'analyse_texte',
      'structure',
      'introduction',
      'developpement',
      'discussion_critique',
      'conclusion',
      'controle',
    ];

    for (final key in requiredTopLevel) {
      if (!json.containsKey(key)) {
        return 'Structure JSON incomplète : $key manquant.';
      }
    }

    // analyse_texte
    final analyse = json['analyse_texte'] as Map<String, dynamic>?;
    if (analyse == null) return 'analyse_texte doit être un objet.';
    final requiredAnalyse = [
      'mots_cles',
      'theme',
      'probleme',
      'these',
      'intention',
      'enjeu'
    ];
    for (final key in requiredAnalyse) {
      if (!analyse.containsKey(key)) return 'analyse_texte.$key manquant.';
    }
    final motsCles = analyse['mots_cles'] as List?;
    if (motsCles == null || motsCles.isEmpty) {
      return 'analyse_texte.mots_cles doit être une liste non vide.';
    }

    // structure
    final structure = json['structure'] as Map<String, dynamic>?;
    if (structure == null) return 'structure doit être un objet.';
    if (!structure.containsKey('mouvement_1') ||
        !structure.containsKey('mouvement_2')) {
      return 'structure doit contenir mouvement_1 et mouvement_2.';
    }
    final m1 = structure['mouvement_1'] as Map<String, dynamic>?;
    final m2 = structure['mouvement_2'] as Map<String, dynamic>?;
    if (m1 == null || m2 == null)
      return 'Les mouvements doivent être des objets.';
    for (final key in [
      'titre',
      'partie_du_texte',
      'idee_principale',
      'fonction'
    ]) {
      if (!m1.containsKey(key)) return 'mouvement_1.$key manquant.';
      if (!m2.containsKey(key)) return 'mouvement_2.$key manquant.';
    }

    // introduction
    final intro = json['introduction'] as Map<String, dynamic>?;
    if (intro == null) return 'introduction doit être un objet.';
    final requiredIntro = [
      'auteur',
      'oeuvre_ou_texte',
      'theme',
      'probleme',
      'these',
      'annonce_mouvement_1',
      'annonce_mouvement_2'
    ];
    for (final key in requiredIntro) {
      if (!intro.containsKey(key)) return 'introduction.$key manquant.';
    }

    // developpement
    final dev = json['developpement'] as Map<String, dynamic>?;
    if (dev == null) return 'developpement doit être un objet.';
    if (!dev.containsKey('mouvement_1') ||
        !dev.containsKey('question_transition') ||
        !dev.containsKey('mouvement_2')) {
      return 'developpement doit contenir mouvement_1, question_transition, mouvement_2.';
    }
    final devM1 = dev['mouvement_1'] as Map<String, dynamic>?;
    final devM2 = dev['mouvement_2'] as Map<String, dynamic>?;
    if (devM1 == null || devM2 == null)
      return 'Les mouvements de développement doivent être des objets.';
    for (final key in [
      'titre',
      'partie_du_texte',
      'idee_principale',
      'explication',
      'mots_et_expressions_importants',
      'arguments',
      'exemples_du_texte',
      'fonction_dans_le_raisonnement'
    ]) {
      if (!devM1.containsKey(key))
        return 'developpement.mouvement_1.$key manquant.';
    }
    for (final key in [
      'titre',
      'partie_du_texte',
      'idee_principale',
      'explication',
      'mots_et_expressions_importants',
      'arguments',
      'exemples_du_texte',
      'progression_de_la_pensee'
    ]) {
      if (!devM2.containsKey(key))
        return 'developpement.mouvement_2.$key manquant.';
    }

    // discussion_critique
    final disc = json['discussion_critique'] as Map<String, dynamic>?;
    if (disc == null) return 'discussion_critique doit être un objet.';
    if (!disc.containsKey('critique_interne') ||
        !disc.containsKey('critique_externe')) {
      return 'discussion_critique doit contenir critique_interne et critique_externe.';
    }
    final ci = disc['critique_interne'] as Map<String, dynamic>?;
    if (ci == null) return 'critique_interne doit être un objet.';
    for (final key in ['coherence', 'points_forts', 'limites']) {
      if (!ci.containsKey(key)) return 'critique_interne.$key manquant.';
    }
    final limites = ci['limites'] as List?;
    if (limites == null || limites.isEmpty) {
      return 'critique_interne.limites doit être une liste non vide.';
    }
    final ce = disc['critique_externe'] as List?;
    if (ce == null || ce.length != 2) {
      return 'critique_externe doit être une liste de 2 éléments.';
    }
    for (int i = 0; i < ce.length; i++) {
      final item = ce[i] as Map<String, dynamic>?;
      if (item == null) return 'critique_externe[$i] doit être un objet.';
      for (final key in [
        'numero',
        'philosophe',
        'position',
        'argument',
        'citation',
        'citation_est_authentique',
        'rapport_avec_le_texte'
      ]) {
        if (!item.containsKey(key))
          return 'critique_externe[$i].$key manquant.';
      }
    }

    // conclusion
    final concl = json['conclusion'] as Map<String, dynamic>?;
    if (concl == null) return 'conclusion doit être un objet.';
    for (final key in [
      'idee_principale',
      'these_auteur',
      'jugement_global',
      'ouverture'
    ]) {
      if (!concl.containsKey(key)) return 'conclusion.$key manquant.';
    }

    // controle
    final ctrl = json['controle'] as Map<String, dynamic>?;
    if (ctrl == null) return 'controle doit être un objet.';
    if (ctrl['nombre_de_mouvements'] != 2) {
      return 'controle.nombre_de_mouvements doit être 2.';
    }
    if (ctrl['nombre_arguments_critiques_externes'] != 2) {
      return 'controle.nombre_arguments_critiques_externes doit être 2.';
    }
    if (ctrl['introduction_redigee'] != false) {
      return 'introduction_redigee doit être false.';
    }
    if (ctrl['conclusion_redigee'] != false) {
      return 'conclusion_redigee doit être false.';
    }
    if (ctrl['commentaire_complet'] != false) {
      return 'commentaire_complet doit être false.';
    }
    if (ctrl['citations_inventees'] != false) {
      return 'citations_inventees doit être false.';
    }

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
  // SNACKBAR ÉLÉGANT
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
                  'Commentaire philosophique',
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
                      'ATELIER PHILOSOPHIQUE',
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
                  'Déconstruis le texte.\nConstruis ta réflexion.',
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
                  'Prof IA décortique le raisonnement philosophique et te guide vers un commentaire structuré, avec discussion critique.',
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
                      'MOUVEMENTS',
                    ),
                    const SizedBox(width: 8),
                    _heroBadge(
                      Icons.menu_book_rounded,
                      'ARGUMENTS',
                    ),
                    const SizedBox(width: 8),
                    _heroBadge(
                      Icons.compare_arrows_rounded,
                      'CRITIQUE',
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
  // COMPOSITEUR DU TEXTE (avec bouton OCR)
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
                          'Colle ou recopie le texte philosophique (extrait d’œuvre, dissertation, etc.).',
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
                        'Exemple :\n« L’homme est né libre, et partout il est dans les fers… »',
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
                      'Un texte précis permet une analyse fine et une discussion critique.',
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
                  // Bouton OCR
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
                  // Bouton Analyser
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
  // CARTE DE REFUS (message de l'IA) – ajoutée
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
                      'Prof IA est spécialisé en commentaire philosophique. Envoie un texte (extrait d’œuvre, dissertation) pour obtenir une analyse structurée.',
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
  // PROF IA EN TRAIN DE TRAVAILLER
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
                    'Lecture du texte • analyse des concepts • construction des mouvements',
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

  // ==========================================================
  // ERREUR
  // ==========================================================

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
                  'Désolé, je suis là pour t’aider à travailler ton commentaire philosophique.',
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
                      'Envoie un texte philosophique (extrait d’œuvre, dissertation, etc.) pour commencer.',
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
  // RÉSULTAT PRINCIPAL
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
          _buildAnalyseTexteSection(result),
          const SizedBox(height: 15),
          _buildStructureSection(result),
          const SizedBox(height: 15),
          _buildIntroductionSection(result),
          const SizedBox(height: 15),
          _buildDeveloppementSection(result),
          const SizedBox(height: 15),
          _buildDiscussionCritiqueSection(result),
          const SizedBox(height: 15),
          _buildConclusionSection(result),
        ],
      ),
    );
  }

  // ==========================================================
  // HEADER RÉSULTAT
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
                'Plan de commentaire philosophique',
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
  // SECTION ANALYSE DU TEXTE
  // ==========================================================

  Widget _buildAnalyseTexteSection(Map<String, dynamic> result) {
    final analyse = Map<String, dynamic>.from(result['analyse_texte'] ?? {});
    final motsCles = (analyse['mots_cles'] as List?) ?? [];

    return _sectionContainer(
      accent: orange,
      icon: Icons.search_rounded,
      label: 'ANALYSE DU TEXTE',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _analyseItem('Thème', analyse['theme']),
          _analyseItem('Problème', analyse['probleme']),
          _analyseItem('Thèse', analyse['these']),
          _analyseItem('Intention', analyse['intention']),
          _analyseItem('Enjeu', analyse['enjeu']),
          const SizedBox(height: 10),
          const Text(
            'MOTS-CLÉS',
            style: TextStyle(
              color: texteSecondaire,
              fontSize: 8.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 6),
          for (var mc in motsCles) _motCleItem(mc as Map<String, dynamic>),
        ],
      ),
    );
  }

  Widget _analyseItem(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: orangeDark,
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

  Widget _motCleItem(Map<String, dynamic> data) {
    final notion = data['notion']?.toString() ?? '';
    final definition = data['definition_contextuelle']?.toString() ?? '';
    final role = data['role_dans_le_texte']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ivoire,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: orange.withOpacity(.10),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            notion,
            style: TextStyle(
              color: orange,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            definition,
            style: const TextStyle(
              color: texte,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
          if (role.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Rôle : $role',
              style: TextStyle(
                color: texteSecondaire,
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ==========================================================
  // SECTION STRUCTURE
  // ==========================================================

  Widget _buildStructureSection(Map<String, dynamic> result) {
    final structure = Map<String, dynamic>.from(result['structure'] ?? {});
    final m1 = Map<String, dynamic>.from(structure['mouvement_1'] ?? {});
    final m2 = Map<String, dynamic>.from(structure['mouvement_2'] ?? {});

    return _sectionContainer(
      accent: vert,
      icon: Icons.account_tree_rounded,
      label: 'STRUCTURE DU RAISONNEMENT',
      child: Column(
        children: [
          _structureMouvement('MOUVEMENT 1', m1, vert),
          const SizedBox(height: 12),
          _structureMouvement('MOUVEMENT 2', m2, orange),
        ],
      ),
    );
  }

  Widget _structureMouvement(
      String title, Map<String, dynamic> data, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ivoire,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withOpacity(.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: .5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            data['titre']?.toString() ?? '',
            style: const TextStyle(
              color: texte,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            data['idee_principale']?.toString() ?? '',
            style: const TextStyle(
              color: texte,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Partie du texte : ${data['partie_du_texte']?.toString() ?? ''}',
            style: TextStyle(
              color: texteSecondaire,
              fontSize: 11,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Fonction : ${data['fonction']?.toString() ?? ''}',
            style: const TextStyle(
              color: texteSecondaire,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // SECTION INTRODUCTION GUIDÉE
  // ==========================================================

  Widget _buildIntroductionSection(Map<String, dynamic> result) {
    final intro = Map<String, dynamic>.from(result['introduction'] ?? {});
    return _sectionContainer(
      accent: jaune,
      icon: Icons.play_arrow_rounded,
      label: 'INTRODUCTION GUIDÉE',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _introItem('Auteur', intro['auteur']),
          _introItem('Œuvre', intro['oeuvre_ou_texte']),
          _introItem('Thème', intro['theme']),
          _introItem('Problème', intro['probleme']),
          _introItem('Thèse', intro['these']),
          _introItem('Annonce mouvement 1', intro['annonce_mouvement_1']),
          _introItem('Annonce mouvement 2', intro['annonce_mouvement_2']),
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
            label.toUpperCase(),
            style: const TextStyle(
              color: texte,
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
  // SECTION DÉVELOPPEMENT
  // ==========================================================

  Widget _buildDeveloppementSection(Map<String, dynamic> result) {
    final dev = Map<String, dynamic>.from(result['developpement'] ?? {});
    final m1 = Map<String, dynamic>.from(dev['mouvement_1'] ?? {});
    final m2 = Map<String, dynamic>.from(dev['mouvement_2'] ?? {});
    final transition = dev['question_transition']?.toString() ?? '';

    return _sectionContainer(
      accent: vert,
      icon: Icons.format_align_justify_rounded,
      label: 'DÉVELOPPEMENT DÉTAILLÉ',
      child: Column(
        children: [
          _buildDevMouvement('MOUVEMENT 1', m1, vert, isFirst: true),
          const SizedBox(height: 14),
          if (transition.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: jaune.withOpacity(.10),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: jaune.withOpacity(.30),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'QUESTION DE TRANSITION',
                    style: TextStyle(
                      color: texte,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    transition,
                    style: const TextStyle(
                      color: texte,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
          _buildDevMouvement('MOUVEMENT 2', m2, orange, isFirst: false),
        ],
      ),
    );
  }

  Widget _buildDevMouvement(
      String title, Map<String, dynamic> data, Color color,
      {required bool isFirst}) {
    final expressions = (data['mots_et_expressions_importants'] as List?) ?? [];
    final arguments = (data['arguments'] as List?) ?? [];
    final exemples = (data['exemples_du_texte'] as List?) ?? [];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ivoire,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withOpacity(.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: .5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            data['titre']?.toString() ?? '',
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Partie du texte : ${data['partie_du_texte']?.toString() ?? ''}',
            style: TextStyle(
              color: texteSecondaire,
              fontSize: 11,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 8),
          _subLabel('Idée principale'),
          Text(
            data['idee_principale']?.toString() ?? '',
            style: const TextStyle(
              color: texte,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          _subLabel('Explication'),
          Text(
            data['explication']?.toString() ?? '',
            style: const TextStyle(
              color: texte,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          if (expressions.isNotEmpty) ...[
            const SizedBox(height: 8),
            _subLabel('Mots et expressions importants'),
            for (var e in expressions)
              _expressionItem(e as Map<String, dynamic>, color),
          ],
          if (arguments.isNotEmpty) ...[
            const SizedBox(height: 8),
            _subLabel('Arguments'),
            for (var arg in arguments)
              _argumentItem(arg as Map<String, dynamic>, color),
          ],
          if (exemples.isNotEmpty) ...[
            const SizedBox(height: 8),
            _subLabel('Exemples du texte'),
            for (var ex in exemples)
              _exempleDevItem(ex as Map<String, dynamic>, color),
          ],
          const SizedBox(height: 8),
          if (isFirst) ...[
            _subLabel('Fonction dans le raisonnement'),
            Text(
              data['fonction_dans_le_raisonnement']?.toString() ?? '',
              style: const TextStyle(
                color: texteSecondaire,
                fontSize: 12.5,
                height: 1.4,
                fontStyle: FontStyle.italic,
              ),
            ),
          ] else ...[
            _subLabel('Progression de la pensée'),
            Text(
              data['progression_de_la_pensee']?.toString() ?? '',
              style: const TextStyle(
                color: texteSecondaire,
                fontSize: 12.5,
                height: 1.4,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _expressionItem(Map<String, dynamic> data, Color color) {
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
                    text: '${data['expression']} : ',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  TextSpan(
                    text: data['explication']?.toString() ?? '',
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

  Widget _argumentItem(Map<String, dynamic> data, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data['argument']?.toString() ?? '',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          Text(
            data['explication']?.toString() ?? '',
            style: const TextStyle(
              color: texteSecondaire,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _exempleDevItem(Map<String, dynamic> data, Color color) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
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
            '« ${data['exemple']} »',
            style: const TextStyle(
              color: texte,
              fontSize: 13,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Rôle : ${data['role']?.toString() ?? ''}',
            style: TextStyle(
              color: texteSecondaire,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _subLabel(String text) {
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

  // ==========================================================
  // SECTION DISCUSSION CRITIQUE
  // ==========================================================

  Widget _buildDiscussionCritiqueSection(Map<String, dynamic> result) {
    final disc = Map<String, dynamic>.from(result['discussion_critique'] ?? {});
    final ci = Map<String, dynamic>.from(disc['critique_interne'] ?? {});
    final ce = (disc['critique_externe'] as List?) ?? [];

    return _sectionContainer(
      accent: orange,
      icon: Icons.compare_arrows_rounded,
      label: 'DISCUSSION CRITIQUE',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _critiqueInterne(ci),
          const SizedBox(height: 16),
          _critiqueExterne(ce),
        ],
      ),
    );
  }

  Widget _critiqueInterne(Map<String, dynamic> data) {
    final limites = (data['limites'] as List?) ?? [];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ivoire,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: orange.withOpacity(.10),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'CRITIQUE INTERNE',
            style: TextStyle(
              color: orangeDark,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 6),
          _subLabel('Cohérence'),
          Text(
            data['coherence']?.toString() ?? '',
            style: const TextStyle(
              color: texte,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          _subLabel('Points forts'),
          Text(
            data['points_forts']?.toString() ?? '',
            style: const TextStyle(
              color: texte,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          if (limites.isNotEmpty) ...[
            const SizedBox(height: 8),
            _subLabel('Limites'),
            for (var l in limites)
              _limiteItem(l as Map<String, dynamic>, orange),
          ],
        ],
      ),
    );
  }

  Widget _limiteItem(Map<String, dynamic> data, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data['limite']?.toString() ?? '',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          Text(
            data['formulation_critique']?.toString() ?? '',
            style: const TextStyle(
              color: texteSecondaire,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _critiqueExterne(List<dynamic> ce) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ivoire,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: vert.withOpacity(.10),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'CRITIQUE EXTERNE',
            style: TextStyle(
              color: vertDark,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          for (var item in ce) _philosopheItem(item as Map<String, dynamic>),
        ],
      ),
    );
  }

  Widget _philosopheItem(Map<String, dynamic> data) {
    final citation = data['citation']?.toString() ?? '';
    final isAuthentic = data['citation_est_authentique'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.black.withOpacity(.05),
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
                  color: vert,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    data['numero']?.toString() ?? '',
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
                data['philosophe']?.toString() ?? '',
                style: const TextStyle(
                  color: texte,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _subLabel('Position'),
          Text(
            data['position']?.toString() ?? '',
            style: const TextStyle(
              color: texte,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 6),
          _subLabel('Argument'),
          Text(
            data['argument']?.toString() ?? '',
            style: const TextStyle(
              color: texte,
              fontSize: 13,
            ),
          ),
          if (citation.isNotEmpty) ...[
            const SizedBox(height: 6),
            _subLabel('Citation'),
            Text(
              '« $citation »',
              style: TextStyle(
                color: vertDark,
                fontSize: 12,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (!isAuthentic)
              Text(
                '(reformulation fidèle)',
                style: TextStyle(
                  color: texteSecondaire,
                  fontSize: 10,
                  fontStyle: FontStyle.italic,
                ),
              ),
          ],
          const SizedBox(height: 6),
          _subLabel('Rapport avec le texte'),
          Text(
            data['rapport_avec_le_texte']?.toString() ?? '',
            style: const TextStyle(
              color: texteSecondaire,
              fontSize: 12,
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
      accent: jaune,
      icon: Icons.flag_rounded,
      label: 'CONCLUSION — INDICATIONS',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _conclusionItem('Idée principale', concl['idee_principale'], orange),
          const SizedBox(height: 8),
          _conclusionItem('Thèse de l\'auteur', concl['these_auteur'], vert),
          const SizedBox(height: 8),
          _conclusionItem('Jugement global', concl['jugement_global'], texte),
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
            label.toUpperCase(),
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
}

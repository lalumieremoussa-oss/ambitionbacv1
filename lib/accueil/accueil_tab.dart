// 📁 lib/tabs/accueil_tab.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

import '../accueil/app_shared.dart';

enum _AccueilView {
  home,
  calendrierComplet,
  resolutionEpreuve,
  rappelComplet,
  videoFullScreen,
}

const String _kVideoUrl =
    'https://pub-a6d2205920ac4bee9cce64d6ab17bff0.r2.dev/publicite/bac.mp4';

const String _kPubBox = 'pubbox';
const String _kLocalVideoAsset = 'assets/data/ambitionbac.mp4';

class AccueilTab extends StatefulWidget {
  final TabUpdateCallback onUpdate;

  const AccueilTab({
    super.key,
    required this.onUpdate,
  });

  @override
  State<AccueilTab> createState() => _AccueilTabState();
}

class _AccueilTabState extends State<AccueilTab> with TickerProviderStateMixin {
  // =====================================================================
  // CONSTANTES DE RÉFÉRENCE POUR LE CHARGEMENT DES RAPPELS
  // =====================================================================
  static const int _referenceMonth = 10; // octobre
  static const int _referenceDay = 1;

  _AccueilView _view = _AccueilView.home;

  Map<String, dynamic>? _selectedRappel;

  Map<String, dynamic>? _programme;
  Map<String, dynamic>? _rappel1;
  Map<String, dynamic>? _rappel2;
  Map<String, dynamic>? _epreuveDuJour;

  bool _estJourEpreuve = false;

  String? _selectedCitationKey;

  late final AnimationController _citationAnimationController;

  // Vidéo
  bool _videoLoading = true;
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;
  bool _videoMuted = true;
  bool _isPlaying = true;

  // =====================================================================
  // INIT
  // =====================================================================

  @override
  void initState() {
    super.initState();

    _citationAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onUpdate(
        title: 'ACCUEIL',
        onBack: null,
      );
    });

    _preload();
  }

  @override
  void dispose() {
    _citationAnimationController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  // =====================================================================
  // PRÉCHARGEMENT
  // =====================================================================

  Future<void> _preload() async {
    await Future.wait([
      _chargerProgramme(),
      _chargerRappelsDuJour(),
    ]);

    if (mounted) {
      setState(() {});
    }

    _preparerVideo();
  }

  // =====================================================================
  // OUTILS UI
  // =====================================================================

  Color get _green => kMatiereGreen;

  Color get _softGreen => const Color(0xFFEAF6EF);

  Color get _darkGreen => const Color(0xFF126B43);

  Widget _sectionTitle({
    required String title,
    String? subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: .2,
              color: _darkGreen,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _smallArrow() {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.82),
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.arrow_forward_rounded,
        size: 17,
        color: _darkGreen,
      ),
    );
  }

  // =====================================================================
  // CALENDRIER SCOLAIRE (inchangé)
  // =====================================================================

  Future<void> _chargerProgramme() async {
    try {
      final raw = await rootBundle.loadString(
        'assets/data/programme.json',
      );

      final decoded = json.decode(raw);

      if (decoded is Map) {
        _programme = Map<String, dynamic>.from(decoded);
      }
    } catch (e) {
      debugPrint('Erreur chargement programme.json : $e');
      _programme = null;
    }
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;

    return DateTime.tryParse(
      value.toString(),
    );
  }

  String _formatDate(DateTime date) {
    const mois = [
      'janvier',
      'février',
      'mars',
      'avril',
      'mai',
      'juin',
      'juillet',
      'août',
      'septembre',
      'octobre',
      'novembre',
      'décembre',
    ];

    return '${date.day} ${mois[date.month - 1]} ${date.year}';
  }

  Map<String, dynamic>? _trimestreActuel(DateTime now) {
    final trimestres = (_programme?['trimestres'] as List?) ?? const [];

    for (final item in trimestres) {
      if (item is! Map) continue;

      final debut = _parseDate(item['debut']);
      final fin = _parseDate(item['fin']);

      if (debut != null &&
          fin != null &&
          !now.isBefore(debut) &&
          !now.isAfter(fin)) {
        return Map<String, dynamic>.from(item);
      }
    }

    return null;
  }

  Map<String, dynamic>? _dernierTrimestre() {
    final trimestres = (_programme?['trimestres'] as List?) ?? const [];

    if (trimestres.isEmpty) return null;

    final dernier = trimestres.last;

    if (dernier is! Map) return null;

    return Map<String, dynamic>.from(dernier);
  }

  bool _apres3eTrimestre(DateTime now) {
    final dernier = _dernierTrimestre();

    if (dernier == null) return false;

    final fin = _parseDate(dernier['fin']);

    return fin != null && now.isAfter(fin);
  }

  Map<String, dynamic>? _prochainElementCalendrier(
    DateTime now,
  ) {
    final candidats = <Map<String, dynamic>>[];

    final evenements = (_programme?['evenements'] as List?) ?? const [];

    for (final item in evenements) {
      if (item is! Map) continue;

      final date = _parseDate(item['date']);

      if (date != null && !date.isBefore(now)) {
        candidats.add({
          'type': 'Événement',
          'nom': item['nom'] ?? 'Événement',
          'date': date,
          'icone': Icons.event_rounded,
        });
      }
    }

    final conges = (_programme?['conges'] as List?) ?? const [];

    for (final item in conges) {
      if (item is! Map) continue;

      final debut = _parseDate(item['debut']);
      final fin = _parseDate(item['fin']);

      if (debut != null) {
        if (!debut.isBefore(now)) {
          candidats.add({
            'type': 'Congé',
            'nom': item['nom'] ?? 'Congé',
            'date': debut,
            'fin': fin,
            'icone': Icons.beach_access_rounded,
          });
        } else if (fin != null && !now.isAfter(fin)) {
          candidats.add({
            'type': 'Congé en cours',
            'nom': item['nom'] ?? 'Congé',
            'date': now,
            'fin': fin,
            'icone': Icons.beach_access_rounded,
          });
        }
      }
    }

    final feries = (_programme?['jours_feries'] as List?) ?? const [];

    for (final item in feries) {
      if (item is! Map) continue;

      final date = _parseDate(item['date']);

      if (date != null && !date.isBefore(now)) {
        candidats.add({
          'type': 'Jour férié',
          'nom': item['nom'] ?? 'Jour férié',
          'date': date,
          'icone': Icons.calendar_today_rounded,
        });
      }
    }

    final examens = (_programme?['examens_fin_annee'] as List?) ?? const [];

    for (final item in examens) {
      if (item is! Map) continue;

      final debut = _parseDate(item['debut']);
      final fin = _parseDate(item['fin']);

      if (debut != null && !debut.isBefore(now)) {
        candidats.add({
          'type': 'Examen',
          'nom': item['nom'] ?? 'Examen',
          'date': debut,
          'fin': fin,
          'icone': Icons.school_rounded,
        });
      } else if (debut != null && fin != null && !now.isAfter(fin)) {
        candidats.add({
          'type': 'Examen en cours',
          'nom': item['nom'] ?? 'Examen',
          'date': now,
          'fin': fin,
          'icone': Icons.school_rounded,
        });
      }
    }

    if (candidats.isEmpty) return null;

    candidats.sort(
      (a, b) {
        final da = a['date'] as DateTime;
        final db = b['date'] as DateTime;
        return da.compareTo(db);
      },
    );

    return candidats.first;
  }

  Widget _buildCalendrierContainer() {
    final now = DateTime.now();

    final trimestre = _trimestreActuel(now);
    final apres3e = _apres3eTrimestre(now);
    final prochain = _prochainElementCalendrier(now);

    String titrePrincipal;
    String sousTitre;
    String? datePrincipale;

    if (apres3e) {
      titrePrincipal = 'Préparation au BEPC';
      sousTitre =
          'Après le troisième trimestre, place à la préparation et aux prochaines périodes scolaires.';

      datePrincipale = null;
    } else if (trimestre != null) {
      titrePrincipal = trimestre['nom']?.toString() ?? 'Trimestre en cours';

      final fin = _parseDate(trimestre['fin']);

      sousTitre =
          fin != null ? 'Fin du trimestre' : 'Période scolaire en cours';

      datePrincipale = fin != null ? _formatDate(fin) : null;
    } else {
      titrePrincipal = 'Calendrier scolaire';

      sousTitre = 'Consultez les prochaines dates importantes.';

      datePrincipale = null;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () {
          setState(() {
            _view = _AccueilView.calendrierComplet;
          });

          widget.onUpdate(
            title: 'CALENDRIER SCOLAIRE',
            onBack: _retourAccueil,
          );
        },
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: _darkGreen.withOpacity(.14),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                stops: [
                  0.0,
                  0.46,
                  0.48,
                  1.0,
                ],
                colors: [
                  kAppOrange,
                  kAppOrange,
                  Color(0xFF2D8A5C),
                  kMatiereGreen,
                ],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(.18),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.calendar_month_rounded,
                          color: Colors.white,
                          size: 23,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'CALENDRIER SCOLAIRE',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      _smallArrow(),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Text(
                    titrePrincipal,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 22,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    sousTitre,
                    style: TextStyle(
                      color: Colors.white.withOpacity(.88),
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                  if (datePrincipale != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(.15),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.schedule_rounded,
                            color: Colors.white,
                            size: 17,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            datePrincipale,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (prochain != null) ...[
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(.12),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withOpacity(.16),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            prochain['icone'] as IconData,
                            color: Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  prochain['type']?.toString() ??
                                      'Prochaine date',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(.72),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  prochain['nom']?.toString() ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _formatDate(
                                    prochain['date'] as DateTime,
                                  ),
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(.82),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 15),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        'Voir le calendrier complet',
                        style: TextStyle(
                          color: Colors.white.withOpacity(.95),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 5),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // =====================================================================
  // CALENDRIER COMPLET (inchangé)
  // =====================================================================

  Widget _calendrierCompletView() {
    final trimestres = (_programme?['trimestres'] as List?) ?? const [];

    final conges = (_programme?['conges'] as List?) ?? const [];

    final feries = (_programme?['jours_feries'] as List?) ?? const [];

    final examens = (_programme?['examens_fin_annee'] as List?) ?? const [];

    final evenements = (_programme?['evenements'] as List?) ?? const [];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
      children: [
        _calendarIntroCard(),
        const SizedBox(height: 16),
        _calendarSection(
          title: 'Découpage de l’année scolaire',
          icon: Icons.school_rounded,
          items: trimestres,
          builder: (item) {
            return _calendarPeriodTile(
              title: item['nom']?.toString() ?? '',
              start: item['debut'],
              end: item['fin'],
            );
          },
        ),
        _calendarSection(
          title: 'Congés et vacances',
          icon: Icons.beach_access_rounded,
          items: conges,
          builder: (item) {
            return _calendarPeriodTile(
              title: item['nom']?.toString() ?? '',
              start: item['debut'],
              end: item['fin'],
            );
          },
        ),
        _calendarSection(
          title: 'Jours fériés',
          icon: Icons.event_available_rounded,
          items: feries,
          builder: (item) {
            final date = _parseDate(item['date']);

            return _simpleCalendarTile(
              title: item['nom']?.toString() ?? '',
              subtitle: date != null ? _formatDate(date) : '',
            );
          },
        ),
        _calendarSection(
          title: 'Événements',
          icon: Icons.event_rounded,
          items: evenements,
          builder: (item) {
            final date = _parseDate(item['date']);

            return _simpleCalendarTile(
              title: item['nom']?.toString() ?? '',
              subtitle: date != null ? _formatDate(date) : '',
            );
          },
        ),
        _calendarSection(
          title: 'Examens de fin d’année',
          icon: Icons.assignment_rounded,
          items: examens,
          builder: (item) {
            return _calendarPeriodTile(
              title: item['nom']?.toString() ?? '',
              start: item['debut'],
              end: item['fin'],
            );
          },
        ),
      ],
    );
  }

  Widget _calendarIntroCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _darkGreen,
            _green,
          ],
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(.13),
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(
              Icons.calendar_month_rounded,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Toutes les dates importantes',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  'Trimestres, congés, événements, jours fériés et examens.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _calendarSection({
    required String title,
    required IconData icon,
    required List items,
    required Widget Function(Map<String, dynamic>) builder,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(19),
        boxShadow: const [
          BoxShadow(
            blurRadius: 12,
            color: Colors.black12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 35,
                height: 35,
                decoration: BoxDecoration(
                  color: _softGreen,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  icon,
                  color: _darkGreen,
                  size: 19,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: _darkGreen,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                'Aucune donnée disponible.',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 12,
                ),
              ),
            )
          else
            ...items.map(
              (item) {
                if (item is Map) {
                  return builder(
                    Map<String, dynamic>.from(item),
                  );
                }

                return const SizedBox.shrink();
              },
            ),
        ],
      ),
    );
  }

  Widget _calendarPeriodTile({
    required String title,
    required dynamic start,
    required dynamic end,
  }) {
    final debut = _parseDate(start);
    final fin = _parseDate(end);

    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBF9),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          Container(
            width: 5,
            height: 38,
            decoration: BoxDecoration(
              color: _green,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if (debut != null) _formatDate(debut),
                    if (fin != null) _formatDate(fin),
                  ].join('  →  '),
                  style: TextStyle(
                    color: Colors.grey.shade600,
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

  Widget _simpleCalendarTile({
    required String title,
    required String subtitle,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBF9),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: kAppOrange,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================================
  // RETOUR
  // =====================================================================

  void _retourAccueil() {
    setState(() {
      _view = _AccueilView.home;
      _selectedRappel = null;
      _selectedCitationKey = null;
    });

    widget.onUpdate(
      title: 'ACCUEIL',
      onBack: null,
    );
  }

  // =====================================================================
  // RAPPELS – NOUVELLE GESTION PAR SEMAINE RÉFÉRENCE (1er OCTOBRE)
  // =====================================================================

  int _dayInCycle(DateTime now) => now.weekday;

  /// Retourne le lundi de la semaine contenant le 1er octobre (référence).
  DateTime _getReferenceWeekStart(DateTime now) {
    int year = now.year;
    DateTime firstOct = DateTime(year, _referenceMonth, _referenceDay);
    // Si on est avant le 1er octobre, on prend l'année précédente
    if (now.isBefore(firstOct)) {
      firstOct = DateTime(year - 1, _referenceMonth, _referenceDay);
    }
    // Trouver le lundi de la semaine (weekday 1 = lundi)
    int offset = firstOct.weekday - 1;
    return firstOct.subtract(Duration(days: offset));
  }

  /// Nombre de semaines écoulées depuis la semaine de référence.
  int _weekIndex(DateTime now) {
    DateTime refMonday = _getReferenceWeekStart(now);
    int diffDays = now.difference(refMonday).inDays;
    if (diffDays < 0) diffDays = 0;
    return diffDays ~/ 7;
  }

  Future<Map<String, dynamic>?> _loadRappelList(
    String matiereCode,
    DateTime now,
  ) async {
    try {
      final raw = await rootBundle.loadString(
        'assets/rappels/$matiereCode.json',
      );

      final decoded = json.decode(raw);

      if (decoded is! List || decoded.isEmpty) {
        return null;
      }

      // Utilisation de l'index basé sur la semaine de référence
      final int weekIndex = _weekIndex(now);
      final int index = weekIndex % decoded.length;

      final item = decoded[index];

      if (item is! Map) {
        return null;
      }

      return {
        'matiere': matiereCode,
        ...Map<String, dynamic>.from(item),
      };
    } catch (e) {
      debugPrint(
        'Erreur chargement rappel $matiereCode : $e',
      );

      return null;
    }
  }

  Future<void> _chargerRappelsDuJour() async {
    final now = DateTime.now();
    final jour = _dayInCycle(now);

    if (jour == 7) {
      _estJourEpreuve = true;

      try {
        final raw = await rootBundle.loadString(
          'assets/rappels/epreuve.json',
        );

        final decoded = json.decode(raw);

        if (decoded is List && decoded.isNotEmpty) {
          // Utilisation de l'index basé sur la semaine de référence
          final int weekIndex = _weekIndex(now);
          final int index = weekIndex % decoded.length;

          if (decoded[index] is Map) {
            _epreuveDuJour = Map<String, dynamic>.from(
              decoded[index],
            );
          }
        }
      } catch (e) {
        debugPrint(
          'Erreur chargement épreuve : $e',
        );
      }

      return;
    }

    _estJourEpreuve = false;

    if (jour == 1 || jour == 2) {
      _rappel1 = await _loadRappelList('fr', now);
      _rappel2 = await _loadRappelList('ge', now);
    } else {
      _rappel1 = await _loadRappelList('ph', now);
      _rappel2 = await _loadRappelList('hi', now);
    }
  }

  String _matiereLabel(String code) {
    switch (code) {
      case 'fr':
        return 'FRANÇAIS';
      case 'ph':
        return 'PHILOSOPHIE';
      case 'hi':
        return 'HISTOIRE';
      case 'ge':
        return 'GÉOGRAPHIE';
      default:
        return code.toUpperCase();
    }
  }

  IconData _matiereIcon(String code) {
    switch (code) {
      case 'fr':
        return Icons.menu_book_rounded;
      case 'ph':
        return Icons.psychology_rounded;
      case 'hi':
        return Icons.account_balance_rounded;
      case 'ge':
        return Icons.public_rounded;
      default:
        return Icons.school_rounded;
    }
  }

  // =====================================================================
  // CARTE RAPPEL
  // =====================================================================

  Widget _rappelContainer(
    Map<String, dynamic>? rappel, {
    required String fallbackLabel,
  }) {
    if (rappel == null) {
      return Container(
        margin: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 6,
        ),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          '$fallbackLabel indisponible.',
          style: TextStyle(
            color: Colors.grey.shade600,
          ),
        ),
      );
    }

    final code = rappel['matiere']?.toString() ?? '';

    final matiere = _matiereLabel(code);

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(21),
        boxShadow: const [
          BoxShadow(
            blurRadius: 13,
            color: Colors.black12,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(21),
          onTap: () {
            setState(() {
              _selectedRappel = rappel;
              _view = _AccueilView.rappelComplet;
              _selectedCitationKey = null;
            });

            widget.onUpdate(
              title: 'RAPPEL COMPLET',
              onBack: _retourAccueil,
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(17),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: _softGreen,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(
                    _matiereIcon(code),
                    color: _darkGreen,
                    size: 23,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        matiere,
                        style: TextStyle(
                          color: _darkGreen,
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                          letterSpacing: .6,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Text(
                        '« ${rappel['citation'] ?? ''} »',
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.35,
                          fontStyle: FontStyle.italic,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        rappel['auteur'] ?? '',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                      if ((rappel['source'] ?? '').toString().isNotEmpty)
                        Text(
                          rappel['source'],
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 11,
                          ),
                        ),
                      const SizedBox(height: 11),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            'Lire le rappel',
                            style: TextStyle(
                              color: _darkGreen,
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.arrow_forward_rounded,
                            color: _darkGreen,
                            size: 16,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // =====================================================================
  // ÉPREUVE
  // =====================================================================

  Widget _epreuveDuJourContainer() {
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _darkGreen,
            _green,
          ],
        ),
        borderRadius: BorderRadius.circular(21),
        boxShadow: [
          BoxShadow(
            color: _darkGreen.withOpacity(.16),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(21),
          onTap: _epreuveDuJour == null
              ? null
              : () {
                  setState(() {
                    _view = _AccueilView.resolutionEpreuve;
                  });

                  widget.onUpdate(
                    title: 'RÉSOLUTION DE L’ÉPREUVE',
                    onBack: _retourAccueil,
                  );
                },
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'ÉPREUVE DU JOUR',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        letterSpacing: 1,
                      ),
                    ),
                    const Spacer(),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                Text(
                  '« ${_epreuveDuJour?['citation'] ?? 'Épreuve indisponible'} »',
                  style: const TextStyle(
                    color: Colors.white,
                    fontStyle: FontStyle.italic,
                    fontSize: 16,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _epreuveDuJour?['auteur'] ?? '',
                  style: TextStyle(
                    color: Colors.white.withOpacity(.78),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // =====================================================================
  // RÉSOLUTION ÉPREUVE (inchangé)
  // =====================================================================

  Widget _resolutionEpreuveView() {
    final data = _epreuveDuJour;

    if (data == null) {
      return const Center(
        child: Text('Épreuve indisponible.'),
      );
    }

    final parties = (data['parties'] as List?) ?? const [];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _detailHeader(
          title: 'ÉPREUVE DU JOUR',
          icon: Icons.assignment_rounded,
        ),
        const SizedBox(height: 12),
        _detailCard(
          title: 'Citation',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '« ${data['citation'] ?? ''} »',
                style: const TextStyle(
                  fontSize: 17,
                  fontStyle: FontStyle.italic,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                data['auteur'] ?? '',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _detailCard(
          title: 'Problématisation',
          child: Text(
            data['problematisation'] ?? '',
            style: const TextStyle(
              height: 1.45,
            ),
          ),
        ),
        const SizedBox(height: 12),
        _detailCard(
          title: 'Plans de développement',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (int i = 0; i < parties.length; i++) ...[
                Text(
                  'Partie ${i + 1} — ${parties[i]['titre'] ?? ''}',
                  style: TextStyle(
                    color: _darkGreen,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 7),
                for (final arg
                    in (parties[i]['arguments'] as List? ?? const []))
                  Padding(
                    padding: const EdgeInsets.only(
                      left: 8,
                      bottom: 6,
                    ),
                    child: Text(
                      '• $arg',
                      style: const TextStyle(
                        height: 1.35,
                      ),
                    ),
                  ),
                if (i < parties.length - 1) const Divider(height: 20),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // =====================================================================
  // RAPPEL COMPLET
  // =====================================================================

  Widget _buildRappelComplet() {
    final rappel = _selectedRappel;

    if (rappel == null) {
      return const Center(
        child: Text('Aucune donnée sélectionnée.'),
      );
    }

    final matiere = rappel['matiere']?.toString() ?? '';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        16,
        16,
        16,
        30,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _detailHeader(
            title: _matiereLabel(matiere),
            icon: _matiereIcon(matiere),
          ),
          const SizedBox(height: 14),
          if (matiere == 'fr' || matiere == 'ph')
            _buildRappelTypeA(rappel)
          else if (matiere == 'hi' || matiere == 'ge')
            _buildRappelTypeB(rappel)
          else
            const Text(
              'Type de rappel non reconnu.',
            ),
        ],
      ),
    );
  }

  Widget _detailHeader({
    required String title,
    required IconData icon,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _darkGreen,
            _green,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 43,
            height: 43,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(.13),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              icon,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: .5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailCard({
    required String title,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            blurRadius: 10,
            color: Colors.black12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              color: _darkGreen,
              fontWeight: FontWeight.w900,
              fontSize: 12,
              letterSpacing: .8,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  // =====================================================================
  // TYPE A : FRANÇAIS / PHILOSOPHIE (MODIFIÉ)
  // =====================================================================

  Widget _buildRappelTypeA(
    Map<String, dynamic> rappel,
  ) {
    final memeAvis = (rappel['citations_meme_avis'] as List?) ?? const [];

    final opposees = (rappel['citations_opposees'] as List?) ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _mainCitationCard(rappel),
        const SizedBox(height: 14),
        if ((rappel['explication'] ?? '').toString().isNotEmpty)
          _mainExplanationCard(
            rappel['explication'].toString(),
          ),
        if (memeAvis.isNotEmpty) ...[
          const SizedBox(height: 22),
          _citationGroupTitle(
            title: 'CITATIONS QUI SOUTIENNENT',
            count: memeAvis.length,
            positive: true,
          ),
          const SizedBox(height: 9),
          ...memeAvis.asMap().entries.map(
            (entry) {
              final index = entry.key;
              final item = Map<String, dynamic>.from(
                entry.value as Map,
              );

              final key = 'support_$index';

              return _animatedCitationItem(
                keyValue: key,
                item: item,
                positive: true,
              );
            },
          ),
        ],
        if (opposees.isNotEmpty) ...[
          const SizedBox(height: 22),
          _citationGroupTitle(
            title: 'CITATIONS QUI S’OPPOSENT',
            count: opposees.length,
            positive: false,
          ),
          const SizedBox(height: 9),
          ...opposees.asMap().entries.map(
            (entry) {
              final index = entry.key;
              final item = Map<String, dynamic>.from(
                entry.value as Map,
              );

              final key = 'oppose_$index';

              return _animatedCitationItem(
                keyValue: key,
                item: item,
                positive: false,
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _mainCitationCard(
    Map<String, dynamic> rappel,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _green.withOpacity(.18),
        ),
        boxShadow: const [
          BoxShadow(
            blurRadius: 11,
            color: Colors.black12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 34,
                decoration: BoxDecoration(
                  color: kAppOrange,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(width: 11),
              Text(
                'CITATION PRINCIPALE',
                style: TextStyle(
                  color: _darkGreen,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  letterSpacing: .8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Text(
            '« ${rappel['citation'] ?? ''} »',
            style: const TextStyle(
              fontSize: 18,
              height: 1.45,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 11),
          Text(
            rappel['auteur'] ?? '',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: Colors.black,
            ),
          ),
          if ((rappel['source'] ?? '').toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                rappel['source'],
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 12,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _mainExplanationCard(
    String explanation,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: _softGreen,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _green.withOpacity(.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'EXPLICATION',
            style: TextStyle(
              color: _darkGreen,
              fontWeight: FontWeight.w900,
              fontSize: 12,
              letterSpacing: .7,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            explanation,
            style: const TextStyle(
              height: 1.45,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================================
  // TYPE B : HISTOIRE / GÉOGRAPHIE (inchangé)
  // =====================================================================

  Widget _buildRappelTypeB(
    Map<String, dynamic> rappel,
  ) {
    final analyseA = (rappel['analyse_a'] as List?) ?? const [];

    final analyseB = (rappel['analyse_b'] as List?) ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _mainCitationCard(rappel),
        const SizedBox(height: 14),
        if ((rappel['contexte'] ?? '').toString().isNotEmpty)
          _mainExplanationCard(
            rappel['contexte'].toString(),
          ),
        if (analyseA.isNotEmpty) ...[
          const SizedBox(height: 22),
          _citationGroupTitle(
            title: 'ANALYSE A',
            count: analyseA.length,
            positive: true,
          ),
          const SizedBox(height: 9),
          ...analyseA.asMap().entries.map(
            (entry) {
              final index = entry.key;
              final item = Map<String, dynamic>.from(
                entry.value as Map,
              );

              return _animatedAnalysisItem(
                keyValue: 'analyse_a_$index',
                item: item,
                positive: true,
              );
            },
          ),
        ],
        if (analyseB.isNotEmpty) ...[
          const SizedBox(height: 22),
          _citationGroupTitle(
            title: 'ANALYSE B',
            count: analyseB.length,
            positive: false,
          ),
          const SizedBox(height: 9),
          ...analyseB.asMap().entries.map(
            (entry) {
              final index = entry.key;
              final item = Map<String, dynamic>.from(
                entry.value as Map,
              );

              return _animatedAnalysisItem(
                keyValue: 'analyse_b_$index',
                item: item,
                positive: false,
              );
            },
          ),
        ],
      ],
    );
  }

  // =====================================================================
  // TITRE GROUPE
  // =====================================================================

  Widget _citationGroupTitle({
    required String title,
    required int count,
    required bool positive,
  }) {
    final color = positive ? _darkGreen : kAppOrange;

    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 13,
              letterSpacing: .6,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 9,
            vertical: 5,
          ),
          decoration: BoxDecoration(
            color: color.withOpacity(.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }

  // =====================================================================
  // CARTE CITATION ANIMÉE (MODIFIÉE)
  // =====================================================================

  Widget _animatedCitationItem({
    required String keyValue,
    required Map<String, dynamic> item,
    required bool positive,
  }) {
    final selected = _selectedCitationKey == keyValue;

    final accent = positive ? _darkGreen : kAppOrange;

    return AnimatedBuilder(
      animation: _citationAnimationController,
      builder: (context, child) {
        final value = _citationAnimationController.value;

        final dx = selected ? 0.0 : ((value - .5) * 1.4);

        final dy = selected ? 0.0 : ((value - .5) * .8);

        return Transform.translate(
          offset: Offset(dx, dy),
          child: child,
        );
      },
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(17),
              onTap: () {
                setState(() {
                  if (_selectedCitationKey == keyValue) {
                    _selectedCitationKey = null;
                  } else {
                    _selectedCitationKey = keyValue;
                  }
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOut,
                width: double.infinity,
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: selected ? accent.withOpacity(.06) : Colors.white,
                  borderRadius: BorderRadius.circular(17),
                  border: Border.all(
                    color: selected
                        ? accent.withOpacity(.42)
                        : Colors.grey.shade200,
                    width: selected ? 1.3 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      blurRadius: selected ? 14 : 7,
                      color: selected
                          ? accent.withOpacity(.10)
                          : Colors.black.withOpacity(.045),
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: accent.withOpacity(.09),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(
                        positive ? Icons.add_rounded : Icons.remove_rounded,
                        color: accent,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item['titre'] ?? 'Citation',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                              color: Colors.black,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            item['auteur'] ?? '',
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (item['source'] != null &&
                              item['source'].toString().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                item['source'].toString(),
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontSize: 11,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedRotation(
                      duration: const Duration(
                        milliseconds: 260,
                      ),
                      turns: selected ? .25 : 0,
                      child: Icon(
                        Icons.add_rounded,
                        color: accent,
                        size: 21,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Explication développée
          AnimatedSize(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            child: selected
                ? Padding(
                    padding: const EdgeInsets.only(
                      top: 7,
                      bottom: 5,
                    ),
                    child: _citationExplanationCard(
                      item: item,
                      accent: accent,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _citationExplanationCard({
    required Map<String, dynamic> item,
    required Color accent,
  }) {
    final explanation = item['explication'] ??
        item['description'] ??
        'Aucune explication disponible.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(15),
        border: Border(
          left: BorderSide(
            color: accent,
            width: 4,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.lightbulb_outline_rounded,
                color: accent,
                size: 18,
              ),
              const SizedBox(width: 7),
              Text(
                'EXPLICATION',
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  letterSpacing: .7,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            explanation.toString(),
            style: const TextStyle(
              fontSize: 13,
              height: 1.45,
              color: Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================================
  // ANALYSES HISTOIRE / GÉOGRAPHIE (inchangé)
  // =====================================================================

  Widget _animatedAnalysisItem({
    required String keyValue,
    required Map<String, dynamic> item,
    required bool positive,
  }) {
    final accent = positive ? _darkGreen : kAppOrange;

    final titre = item['titre'] ?? 'Sans titre';

    final illustration = item['illustration'] ?? '';

    final description = item['description'] ?? '';

    final selected = _selectedCitationKey == keyValue;

    return AnimatedBuilder(
      animation: _citationAnimationController,
      builder: (context, child) {
        final value = _citationAnimationController.value;

        return Transform.translate(
          offset: selected
              ? Offset.zero
              : Offset(
                  (value - .5) * 1.2,
                  (value - .5) * .7,
                ),
          child: child,
        );
      },
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(17),
              onTap: () {
                if (illustration.toString().isEmpty) {
                  return;
                }

                setState(() {
                  if (_selectedCitationKey == keyValue) {
                    _selectedCitationKey = null;
                  } else {
                    _selectedCitationKey = keyValue;
                  }
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(17),
                  border: Border.all(
                    color: selected
                        ? accent.withOpacity(.4)
                        : Colors.grey.shade200,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: accent.withOpacity(.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.analytics_outlined,
                        color: accent,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            titre.toString(),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                              color: Colors.black,
                            ),
                          ),
                          if (description.toString().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                description.toString(),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          if (item['auteur'] != null &&
                              item['auteur'].toString().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                item['auteur'].toString(),
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          if (item['source'] != null &&
                              item['source'].toString().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                item['source'].toString(),
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontSize: 11,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Icon(
                      selected
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: accent,
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            child: selected
                ? Padding(
                    padding: const EdgeInsets.only(
                      top: 7,
                    ),
                    child: _citationExplanationCard(
                      item: item,
                      accent: accent,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  // =====================================================================
  // VIDÉO
  // =====================================================================

  String _currentWeekKey(DateTime now) {
    final monday = now.subtract(
      Duration(days: now.weekday - 1),
    );

    return '${monday.year}-'
        '${monday.month.toString().padLeft(2, '0')}-'
        '${monday.day.toString().padLeft(2, '0')}';
  }

  Future<void> _preparerVideo() async {
    try {
      final box = await Hive.openBox(_kPubBox);

      final now = DateTime.now();
      final weekKey = _currentWeekKey(now);

      final storedWeekKey = box.get('weekKey');
      final storedPath = box.get('path') as String?;

      if (storedWeekKey == weekKey &&
          storedPath != null &&
          File(storedPath).existsSync()) {
        await _initVideoController(File(storedPath).path, isAsset: false);
        if (mounted) setState(() => _videoLoading = false);
        return;
      }

      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity != ConnectivityResult.none) {
        try {
          final response = await http.get(Uri.parse(_kVideoUrl));
          if (response.statusCode == 200) {
            final dir = await getApplicationDocumentsDirectory();
            final file = File('${dir.path}/bac_semaine.mp4');
            await file.writeAsBytes(response.bodyBytes);
            await box.put('weekKey', weekKey);
            await box.put('path', file.path);
            await _initVideoController(file.path, isAsset: false);
            if (mounted) setState(() => _videoLoading = false);
            return;
          }
        } catch (e) {
          debugPrint('Erreur téléchargement vidéo : $e');
        }
      }

      // Fallback asset
      await _initVideoController(_kLocalVideoAsset, isAsset: true);
      if (mounted) setState(() => _videoLoading = false);
    } catch (e) {
      debugPrint('Erreur préparation vidéo : $e');
      try {
        await _initVideoController(_kLocalVideoAsset, isAsset: true);
      } catch (_) {}
      if (mounted) setState(() => _videoLoading = false);
    }
  }

  Future<void> _initVideoController(String path,
      {required bool isAsset}) async {
    await _videoController?.dispose();

    VideoPlayerController controller;
    if (isAsset) {
      controller = VideoPlayerController.asset(path);
    } else {
      controller = VideoPlayerController.file(File(path));
    }

    _videoController = controller;

    try {
      await controller.initialize();
      await controller.setVolume(0);
      await controller.setLooping(true);
      await controller.play();
      _isPlaying = true;

      if (mounted) {
        setState(() {
          _isVideoInitialized = true;
          _videoMuted = true;
        });
      }
    } catch (e) {
      debugPrint('Erreur initialisation vidéo : $e');
      if (mounted) {
        setState(() {
          _isVideoInitialized = false;
        });
      }
    }
  }

  void _togglePlayPause() {
    if (_videoController == null || !_isVideoInitialized) return;

    setState(() {
      _isPlaying = !_isPlaying;
      if (_isPlaying) {
        _videoController!.play();
      } else {
        _videoController!.pause();
      }
    });
  }

  void _openFullScreenVideo() {
    if (_videoController == null || !_isVideoInitialized) {
      return;
    }

    setState(() {
      _view = _AccueilView.videoFullScreen;
    });

    widget.onUpdate(
      title: 'VIDÉO PLEIN ÉCRAN',
      onBack: _retourVideo,
    );
  }

  void _retourVideo() {
    _videoController?.setVolume(
      _videoMuted ? 0 : 1,
    );

    setState(() {
      _view = _AccueilView.home;
    });

    widget.onUpdate(
      title: 'ACCUEIL',
      onBack: null,
    );
  }

  void _toggleMuteFullScreen() {
    setState(() {
      _videoMuted = !_videoMuted;

      _videoController?.setVolume(
        _videoMuted ? 0 : 1,
      );
    });
  }

  Widget _videoFullScreenView() {
    if (_videoController == null || !_isVideoInitialized) {
      return const Center(
        child: Text(
          'Vidéo non disponible',
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white,
                  ),
                  onPressed: _retourVideo,
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(
                    _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                  ),
                  onPressed: _togglePlayPause,
                ),
                IconButton(
                  icon: Icon(
                    _videoMuted
                        ? Icons.volume_off_rounded
                        : Icons.volume_up_rounded,
                    color: Colors.white,
                  ),
                  onPressed: _toggleMuteFullScreen,
                ),
              ],
            ),
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: _videoController!.value.aspectRatio,
                  child: VideoPlayer(
                    _videoController!,
                  ),
                ),
              ),
            ),
            VideoProgressIndicator(
              _videoController!,
              allowScrubbing: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _videoContainer() {
    return Container(
      margin: const EdgeInsets.fromLTRB(
        16,
        18,
        16,
        16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            title: 'VIDÉO DE LA SEMAINE',
          ),
          const SizedBox(height: 2),
          GestureDetector(
            onTap: _openFullScreenVideo,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(
                    blurRadius: 12,
                    color: Colors.black12,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (_videoLoading)
                      const CircularProgressIndicator(
                        color: kAppOrange,
                      )
                    else if (_isVideoInitialized && _videoController != null)
                      VideoPlayer(
                        _videoController!,
                      )
                    else
                      const Text(
                        'Vidéo indisponible hors connexion',
                        style: TextStyle(
                          color: Colors.white70,
                        ),
                      ),
                    if (!_videoLoading && _isVideoInitialized)
                      Container(
                        color: Colors.black26,
                        child: const Icon(
                          Icons.play_circle_fill_rounded,
                          color: Colors.white70,
                          size: 58,
                        ),
                      ),
                    if (!_videoLoading && _isVideoInitialized)
                      Positioned(
                        bottom: 9,
                        right: 9,
                        child: Row(
                          children: [
                            GestureDetector(
                              onTap: _togglePlayPause,
                              child: Container(
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  _isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                _videoMuted
                                    ? Icons.volume_off_rounded
                                    : Icons.volume_up_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 2,
            ),
            child: Text(
              'Appuyez sur la vidéo pour l’agrandir',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================================
  // BUILD
  // =====================================================================

  @override
  Widget build(BuildContext context) {
    switch (_view) {
      case _AccueilView.calendrierComplet:
        return _calendrierCompletView();

      case _AccueilView.resolutionEpreuve:
        return _resolutionEpreuveView();

      case _AccueilView.rappelComplet:
        return _buildRappelComplet();

      case _AccueilView.videoFullScreen:
        return _videoFullScreenView();

      case _AccueilView.home:
        return ListView(
          padding: const EdgeInsets.only(
            bottom: 20,
          ),
          children: [
            _buildCalendrierContainer(),
            _sectionTitle(
              title: 'RAPPELS DE LA SEMAINE',
            ),
            if (_estJourEpreuve)
              _epreuveDuJourContainer()
            else ...[
              _rappelContainer(
                _rappel1,
                fallbackLabel: 'Rappel indisponible',
              ),
              _rappelContainer(
                _rappel2,
                fallbackLabel: 'Rappel indisponible',
              ),
            ],
            _videoContainer(),
          ],
        );
    }
  }
}

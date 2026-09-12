// 📁 lib/statistiques_page.dart

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StatistiquesPage extends StatefulWidget {
  const StatistiquesPage({super.key});

  @override
  State<StatistiquesPage> createState() => _StatistiquesPageState();
}

class _StatistiquesPageState extends State<StatistiquesPage> {
  final SupabaseClient _client = Supabase.instance.client;
  bool loading = true;
  double tauxReussiteGlobal = 0.0;
  int totalQuizzesPlayed = 0;
  List<Map<String, dynamic>> statsMatieres = [];
  Box? statsBox;

  // Conditions de badges
  bool _badgeChefDeClasse = false;
  bool _badgeEleveStudieux = false;
  bool _badgeCerveauDuGenie = false;
  bool _badgeVitesseLumiere = false;
  bool _badgeAngeDuSavoir = false;

  // ----------------- LISTES STATIQUES DES RÉCOMPENSES -----------------
  final List<Map<String, String>> _tropheesGenerauxList = [
    {"matiere": "Mathématiques", "nom": "🧠 Mathématicien du pays", "message": "Ahhh mais toi là, tu as mis calculatrice dans ton cerveau ! Respect total, futur Pythagore de Babi !"},
    {"matiere": "HISTOIRE", "nom": "📜 Vieux père du savoir", "message": "Tu connais l’histoire du monde hein ! Félicitations, historien en puissance !"},
    {"matiere": "GÉOGRAPHIE", "nom": "🌍 GPS humain", "message": "Toi là, tu connais la carte du monde comme ton quartier. Le pays est fier de toi !"},
    {"matiere": "PHYSIQUE-CHIMIE", "nom": "⚗️ Ingénieur du quartier", "message": "Les molécules tremblent quand tu entres en classe. Bravo l’ingénieur de demain !"},
    {"matiere": "SVT", "nom": "🌱 Docteur Nature", "message": "Tu es prêt pour la blouse blanche ! On t’attend à l’hôpital là-bas pour soigner les gens !"},
    {"matiere": "PHILOSOPHIE", "nom": "🧠 Le Sage de la cité", "message": "Tes idées là, même Socrate va s’asseoir pour t’écouter. Chapeau, penseur !"},
    {"matiere": "FRANÇAIS", "nom": "✍️ Maître de la parole", "message": "Ton français là est doux comme la musique ! Félicitations, écrivain du futur !"},
    {"matiere": "ANGLAIS", "nom": "🇬🇧 English Bôy / English Girl", "message": "Même les Anglais vont dire que tu parles bien ! Continue, champion international !"},
    {"matiere": "CULTURE GÉNÉRALE", "nom": "🧠 Bibliothèque vivante", "message": "Tu as mis Google en danger ! On t’appelle pour les quiz là !"},
    {"matiere": "ALLEMAND", "nom": "Chef de la Bundesliga", "message": "Ton allemand là est propre ! Même à Berlin, on va t’inviter pour donner cours. Respekt !"},
    {"matiere": "ESPAGNOL", "nom": "Señor / Señorita du savoir", "message": "Olayyy ! Ton espagnol là est sucré comme churros. Vamos ! Tu vas loin mon ami !"},
    {"matiere": "EPS", "nom": "Champion Olympique de la cour", "message": "Tu es concentré comme si les Jeux Olympiques se jouaient dans ta cour ! Intelligence, style… Boss, on a besoin de toi à l’INJS hein !"},
  ];

  final List<Map<String, String>> _badgesSpeciauxList = [
    {"nom": "🥇 Trophée Cerveau du génie", "description": "A obtenu 100% de bonnes réponses à un quiz.", "message": "Félicitations, tu as obtenu 100% de bonnes réponses à un quiz !"},
    {"nom": "🏅 Badge Chef de Classe", "description": "A obtenu une moyenne de plus de 19/20 dans une matière.", "message": "👉 C’est toi même on doit nommer chef ici. Tu travailles proprement !"},
    {"nom": "⚡ Trophée Vitesse de lumière", "description": "A répondu correctement à toutes les questions en moins de 15 secondes par question.", "message": "👉 Tu vas trop vite là ! Tu veux couper-décaler le système ou bien ? Bravo !"},
    {"nom": "🥇 Badge Élève studieux(se)", "description": "A fait plus de 50 quiz dans l’application.", "message": "👉 Personne ne cause avec toi. Tu es le doyen des quiz maintenant. Chapeau chef !"},
    {"nom": "🛡️ Trophée L’ange du savoir", "description": "A réussi 2 séries de quiz consécutifs sans échec.", "message": "👉 Tu boucantes le savoir là hein ! Si tu deviens ministre dans pays là, faut pas nous oublier hein !"},
  ];

  @override
  void initState() {
    super.initState();
    _chargerStatistiques();
  }

  // ----------------- Chargement et Calcul des statistiques (UNIFIÉ) -----------------
  Future<void> _chargerStatistiques() async {
    final userId = _client.auth.currentUser?.id;
    List<Map<String, dynamic>> onlineStats = [];
    List<Map<String, dynamic>> offlineStats = [];
    // Set pour suivre les quiz déjà synchronisés (évite les doublons)
    Set<String> syncedSectionIds = {};

    // 1. Initialiser Hive et ouvrir la boîte
    try {
      statsBox = Hive.isBoxOpen('userStatsBox')
          ? Hive.box('userStatsBox')
          : await Hive.openBox('userStatsBox');
    } catch (_) { /* ignore */ }

    // 2. Récupérer toutes les entrées de quiz joués depuis Supabase (Online)
    if (userId != null) {
      try {
        onlineStats = await _client
            .from('statistiques_utilisateur')
            .select('matiere, score_questions, total_tentatives, sectionId')
            .eq('user_id', userId);

        syncedSectionIds = onlineStats.map((s) => s['sectionId'].toString()).toSet();

      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Erreur de connexion : statistiques en ligne non chargées. Affichage des stats locales.'),
            duration: Duration(seconds: 3),
          ));
        }
      }
    }

    // 3. Récupérer toutes les entrées depuis Hive (Offline)
    if (statsBox != null) {
      for (var key in statsBox!.keys) {
        final dynamic hiveItemRaw = statsBox!.get(key);
        // S'assurer que l'élément est une Map
        if (hiveItemRaw is Map) {
          final Map<String, dynamic> hiveItem = Map<String, dynamic>.from(hiveItemRaw);

          if (hiveItem.containsKey('sectionId') && !syncedSectionIds.contains(hiveItem['sectionId'].toString())) {

            offlineStats.add({
              'matiere': hiveItem['matiere'],
              'score_questions': hiveItem['score_questions'],
              'total_tentatives': hiveItem['total_tentatives'],
            });
          }
        }
      }
    }

    // 4. Fusionner les deux listes pour les calculs finaux
    final List<Map<String, dynamic>> allStats = [...onlineStats, ...offlineStats];
    totalQuizzesPlayed = allStats.length;

    // Si l'utilisateur n'était pas connecté ET il n'y a pas de stats locales
    if (userId == null && allStats.isEmpty) {
      setState(() => loading = false);
      return;
    }
    // 5. Agrégation et calculs complets
final Map<String, Map<String, int>> aggregation = {};
int globalTentatives = 0;
int globalSucces = 0;

// Variables pour le calcul des badges
int consecutiveSuccessQuizzes = 0;
bool onePerfectQuizFound = false;
bool oneSpeedQuizFound = false;

// --------------- Boucle d’agrégation principale ---------------
for (var item in allStats) {
  final String matiere = item['matiere'] ?? 'Inconnue';
  final int succes = item['score_questions'] ?? 0;
  final int tentatives = item['total_tentatives'] ?? 0;
  final double totalResponseTime = (item['temps_reponse_total'] ?? 0).toDouble();
  final double averageTimePerQuestion =
      tentatives > 0 ? totalResponseTime / tentatives : 0;

  // 🔹 LOGIQUE DES BADGES
  if (succes == tentatives && tentatives > 0) {
    onePerfectQuizFound = true; // 100% de réussite
  }

  if (succes == tentatives) {
    consecutiveSuccessQuizzes++;
  } else {
    consecutiveSuccessQuizzes = 0;
  }

  if (succes == tentatives && averageTimePerQuestion <= 15.0 && tentatives > 0) {
    oneSpeedQuizFound = true; // Rapidité
  }

  // 🔹 AGRÉGATION PAR MATIÈRE
  final entry = aggregation.putIfAbsent(matiere, () => {
        'succes': 0,
        'tentatives': 0,
      });
  entry['succes'] = entry['succes']! + succes;
  entry['tentatives'] = entry['tentatives']! + tentatives;

  globalSucces += succes;
  globalTentatives += tentatives;
}

// --------------- Calculs dérivés ---------------

// 6️⃣ Calcul du Taux de Réussite Global
tauxReussiteGlobal =
    globalTentatives == 0 ? 0.0 : (globalSucces / globalTentatives) * 100;

// 7️⃣ Construction de la liste des moyennes par matière
statsMatieres = aggregation.entries.map((e) {
  final matiere = e.key;
  final succes = e.value['succes']!;
  final tentatives = e.value['tentatives']!;
  final moyenne = tentatives == 0 ? 0.0 : (succes / tentatives) * 20.0;
  return {
    'matiere': matiere,
    'questions': succes,
    'tentatives': tentatives,
    'moyenne': moyenne,
  };
}).toList();

// 8️⃣ Mise à jour des badges spéciaux
_badgeChefDeClasse =
    statsMatieres.any((m) => (m['moyenne'] as double) >= 19.0);
_badgeEleveStudieux = totalQuizzesPlayed >= 50;
_badgeCerveauDuGenie = onePerfectQuizFound;
_badgeAngeDuSavoir = consecutiveSuccessQuizzes >= 2;
_badgeVitesseLumiere = oneSpeedQuizFound;

// 🔹 Rafraîchissement de l’UI
setState(() {
  loading = false;
});}

  // ----------------- LOGIQUE DES RÉCOMPENSES -----------------

  // Détermine les trophées de Matière gagnés (Moyenne >= 15/20)
  List<Map<String, dynamic>> _getTropheesGagnes() {
    final List<Map<String, dynamic>> tropheesGagnes = [];
    for (var stat in statsMatieres) {
      final String matiere = stat['matiere'];
      final double moyenne = stat['moyenne'];

      if (moyenne >= 15.0) {
        final match = _tropheesGenerauxList.firstWhere(
              (t) => t['matiere'] == matiere,
          orElse: () => {},
        );
        if (match.isNotEmpty) {
          tropheesGagnes.add({
            'matiere': matiere,
            'nom': match['nom']!,
            'message': match['message']!,
            'moyenne': moyenne,
          });
        }
      }
    }
    return tropheesGagnes;
  }

  // Détermine les Badges Spéciaux gagnés
  List<Map<String, dynamic>> _getBadgesGagnes() {
    final List<Map<String, dynamic>> badgesGagnes = [];

    // Fonction utilitaire pour trouver le badge dans la liste statique
    Map<String, String> _findBadge(String nomPartiel) {
      return _badgesSpeciauxList.firstWhere(
            (b) => b['nom']!.contains(nomPartiel),
        orElse: () => {},
      );
    }

    // Badge Chef de Classe (Moyenne > 19/20)
    if (_badgeChefDeClasse) {
      badgesGagnes.add({..._findBadge('Chef de Classe'), 'gagne': true});
    }

    // Badge Élève Studieux (Plus de 50 quiz)
    if (_badgeEleveStudieux) {
      badgesGagnes.add({..._findBadge('Élève studieux'), 'gagne': true});
    }

    // NOUVEAU: Trophée Cerveau du génie (100% de bonnes réponses à un quiz)
    if (_badgeCerveauDuGenie) {
      badgesGagnes.add({..._findBadge('Cerveau du génie'), 'gagne': true});
    }

    // NOUVEAU: Trophée Vitesse de lumière (15 secondes par question)
    if (_badgeVitesseLumiere) {
      badgesGagnes.add({..._findBadge('Vitesse de lumière'), 'gagne': true});
    }
    
    // NOUVEAU: Trophée L’ange du savoir (2 séries consécutives sans échec)
    if (_badgeAngeDuSavoir) {
      badgesGagnes.add({..._findBadge('L’ange du savoir'), 'gagne': true});
    }

    return badgesGagnes;
  }
  // ----------------- Section Résumé global -----------------
  Widget _resumeGlobal() {
    final top2 = List<Map<String, dynamic>>.from(statsMatieres)
      ..sort((a, b) => (b['moyenne'] ?? 0).compareTo(a['moyenne'] ?? 0));
    final meilleures = top2.take(2).toList();

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            SizedBox(
              width: 120,
              height: 120,
              child: PieChart(
                PieChartData(
                  centerSpaceRadius: 30,
                  sections: [
                    PieChartSectionData(
                      value: tauxReussiteGlobal,
                      title: "${tauxReussiteGlobal.toStringAsFixed(0)}%",
                      color: Colors.green,
                      radius: 45,
                      titleStyle: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16),
                    ),
                    PieChartSectionData(
                        value: 100 - tauxReussiteGlobal,
                        color: Colors.redAccent,
                        title: ""),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Score moyen global",
                      style:
                      TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Text("${tauxReussiteGlobal.toStringAsFixed(1)} % de réussite"),
                  const SizedBox(height: 12),
                  const Text("Matières les plus performantes :",
                      style:
                      TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  for (var m in meilleures)
                    Text("${m['matiere']} — ${(m['moyenne'] ?? 0).toStringAsFixed(1)}/20"),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------- Bloc par matière -----------------
  Widget _blocMatiere(Map<String, dynamic> m) {
    final moy = (m['moyenne'] ?? 0.0).toDouble();
    final progress = (moy / 20).clamp(0.0, 1.0);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(m['matiere'],
                style:
                const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 6),
            Text(
                "Questions réussies : ${m['questions']} / Tentatives : ${m['tentatives']}"),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              color: moy >= 15.0 ? Colors.green.shade700 : Colors.orange, // Couleur dynamique
              backgroundColor: Colors.grey.shade200,
            ),
            const SizedBox(height: 4),
            Text("Moyenne : ${moy.toStringAsFixed(2)} / 20"),
          ],
        ),
      ),
    );
  }

  // ----------------- Récompenses et trophées (Dynamique) -----------------
  Widget _recompenses() {
    final tropheesGagnes = _getTropheesGagnes();
    final badgesGagnes = _getBadgesGagnes();

    // Déterminer les badges spéciaux qui n'ont PAS été gagnés
    final badgesADebloquer = _badgesSpeciauxList.where((b) => !badgesGagnes.any((bg) => bg['nom'] == b['nom'])).toList();


    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Trophées de Maîtrise (Moyenne ≥ 15/20)",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 8),
        if (tropheesGagnes.isEmpty)
          const Center(child: Text("Aucun trophée de matière gagné pour l'instant.")),

        ...tropheesGagnes.map((t) => Card(
          color: Colors.white,
          child: ListTile(
            leading: const Icon(Icons.emoji_events, color: Colors.amber, size: 30),
            title: Text("${t['matiere']} — ${t['nom']}"),
            subtitle: Text("Moyenne: ${(t['moyenne'] as double).toStringAsFixed(2)}/20. ${t['message']!}"),
          ),
        )),

        const SizedBox(height: 18),
        const Text("Badges Spéciaux Gagnés",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 8),
        if (badgesGagnes.isEmpty)
          const Center(child: Text("Aucun badge spécial gagné.")),

        ...badgesGagnes.map((b) => Card(
          color: Colors.white,
          child: ListTile(
            leading: const Icon(Icons.star, color: Colors.green, size: 30),
            title: Text(b['nom']!),
            subtitle: Text(b['message']!),
          ),
        )),

        const SizedBox(height: 18),
        const Text("Badges à Débloquer",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.grey)),
        const SizedBox(height: 8),

        ...badgesADebloquer.map((b) => Card(
          color: Colors.grey.shade100,
          child: ListTile(
            leading: Icon(Icons.lock, color: Colors.grey.shade400, size: 30),
            title: Text(b['nom']!, style: const TextStyle(color: Colors.grey)),
            subtitle: Text(b['description']!, style: const TextStyle(color: Colors.grey)),
          ),
        )),
      ],
    );
  }

  // ----------------- UI principale -----------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF4F0),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFF8C00),
        centerTitle: true,
        title: const Text("Mes Statistiques",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: CircleAvatar(
              backgroundColor: Colors.white,
              radius: 16,
              child: Padding(
                padding: const EdgeInsets.all(2.0),
                child: Image.asset('assets/images/outils/logo_ambitionbac.png'),
              ),
            ),
          ),
        ],
      ),
      body: loading
          ? const Center(
        child: CircularProgressIndicator(color: Color(0xFFFF8C00)),
      )
          : Stack(
        children: [
          // Filigrane
          Center(
            child: Opacity(
              opacity: 0.2,
              child: Image.asset(
                  'assets/images/outils/logo_ambition.png',
                  width: 250,
                  fit: BoxFit.contain),
            ),
          ),
          SingleChildScrollView(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              children: [
                _resumeGlobal(),
                const SizedBox(height: 12),
                const Text("Statistiques générales par matière",
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 6),

                // ✅ Correction tri + map
                Builder(
                  builder: (_) {
                    final List<Map<String, dynamic>> sortedMatieres =
                    List<Map<String, dynamic>>.from(statsMatieres);
                    sortedMatieres.sort((a, b) =>
                        (b['moyenne'] as double)
                            .compareTo(a['moyenne'] as double));
                    return Column(
                      children:
                      sortedMatieres.map(_blocMatiere).toList(),
                    );
                  },
                ),

                const SizedBox(height: 18),
                _recompenses(),
              ],
            ),
          ),
        ],
      ),
    );
  }

}
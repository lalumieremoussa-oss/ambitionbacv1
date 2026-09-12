// 📁 lib/classement_page.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -----------------------------------------------------------------------------
// 0. CONSTANTES GLOBALES
// -----------------------------------------------------------------------------
const Color _primaryColor = Color(0xFFFF8C00);
const String _logoAmbitionBac = 'assets/images/outils/logo_ambitionbac.png';
const String _logoWatermark = 'assets/images/outils/logo_ambition.png';

// -----------------------------------------------------------------------------
// 1. MODÈLE DE DONNÉES (RankEntry)
// -----------------------------------------------------------------------------

class RankEntry {
  final int rank;
  final String nickname;
  final String city;
  final String region;
  final double rankingScore;
  final int totalSuccesses;
  final bool isCurrentUser;
  final String matricule;

  RankEntry({
    required this.rank,
    required this.nickname,
    required this.city,
    required this.region,
    required this.rankingScore,
    required this.totalSuccesses,
    required this.matricule,
    this.isCurrentUser = false,
  });

  factory RankEntry.fromMap(Map<String, dynamic> map, String currentMatricule) {
    return RankEntry(
      rank: (map['rank'] as num).toInt(),
      // Utilisation de 'full_identity' renvoyé par votre SQL
      nickname: map['full_identity'] as String? ?? 'Élève Anonyme',
      city: map['city'] as String? ?? 'N/A',
      region: map['region'] as String? ?? 'N/A',
      rankingScore: (map['ranking_score'] as num).toDouble(),
      totalSuccesses: (map['total_successes'] as num).toInt(),
      matricule: map['matricule'] as String? ?? '',
      isCurrentUser: map['matricule'] == currentMatricule,
    );
  }
}

// -----------------------------------------------------------------------------
// 2. SERVICE DE DONNÉES (RankService)
// -----------------------------------------------------------------------------

class RankService {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> _fetchRawRanking() async {
    try {
      final response = await _client.rpc('get_national_ranking');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint("Erreur RPC Classement: $e");
      return [];
    }
  }

  Future<Map<String, String>> _fetchLocalUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'matricule': prefs.getString('matricule') ?? '',
      'city': prefs.getString('ville') ?? 'N/A',
      'region': prefs.getString('region') ?? 'N/A',
    };
  }

  Future<List<RankEntry>> fetchRanking(String type) async {
    final userInfo = await _fetchLocalUserInfo();
    final String myMatricule = userInfo['matricule']!;

    if (myMatricule.isEmpty) return [];

    final allNationalRanks = await _fetchRawRanking();

    List<RankEntry> allEntries = allNationalRanks
        .map((data) => RankEntry.fromMap(data, myMatricule))
        .toList();

    if (allEntries.isEmpty) return [];

    if (type == 'national') {
      List<RankEntry> top10 = allEntries.take(10).toList();
      bool userInTop10 = top10.any((e) => e.isCurrentUser);

      if (!userInTop10) {
        try {
          final userEntry = allEntries.firstWhere((e) => e.isCurrentUser);
          top10.add(userEntry);
        } catch (e) {/* Utilisateur sans statistiques */}
      }
      return top10;
    } else {
      final String filterValue =
          type == 'city' ? userInfo['city']! : userInfo['region']!;

      final localRanks = allEntries.where((e) {
        return type == 'city' ? e.city == filterValue : e.region == filterValue;
      }).toList();

      // Recalcul du rang local (1, 2, 3...)
      return localRanks.asMap().entries.map((entry) {
        final original = entry.value;
        return RankEntry(
          rank: entry.key + 1,
          nickname: original.nickname,
          city: original.city,
          region: original.region,
          rankingScore: original.rankingScore,
          totalSuccesses: original.totalSuccesses,
          matricule: original.matricule,
          isCurrentUser: original.isCurrentUser,
        );
      }).toList();
    }
  }
}

// -----------------------------------------------------------------------------
// 3. UI - CLASSEMENT PAGE
// -----------------------------------------------------------------------------

class ClassementPage extends StatefulWidget {
  const ClassementPage({super.key});

  @override
  State<ClassementPage> createState() => _ClassementPageState();
}

class _ClassementPageState extends State<ClassementPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final RankService _rankService = RankService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('ESPACE CLASSEMENT',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: _primaryColor,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Image.asset(_logoAmbitionBac, width: 35),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Ville'),
            Tab(text: 'Région'),
            Tab(text: 'National'),
          ],
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: 0.1,
              child: Image.asset(_logoWatermark, fit: BoxFit.contain),
            ),
          ),
          TabBarView(
            controller: _tabController,
            children: [
              _RankListView(
                  future: _rankService.fetchRanking('city'), type: 'city'),
              _RankListView(
                  future: _rankService.fetchRanking('region'), type: 'region'),
              _RankListView(
                  future: _rankService.fetchRanking('national'),
                  type: 'national'),
            ],
          ),
        ],
      ),
    );
  }
}

class _RankListView extends StatelessWidget {
  final Future<List<RankEntry>> future;
  final String type;
  const _RankListView({required this.future, required this.type});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<RankEntry>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: _primaryColor));
        }
        if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(
              child: Text("Aucune donnée disponible pour le moment"));
        }

        final entries = snapshot.data!;
        return ListView.builder(
          padding: const EdgeInsets.only(top: 10, bottom: 20),
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final entry = entries[index];

            // Séparateur pour l'utilisateur hors top 10 national
            bool showDivider = type == 'national' &&
                index > 0 &&
                entry.rank > 10 &&
                entries[index - 1].rank <= 10;

            return Column(
              children: [
                if (showDivider)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Divider(thickness: 2, indent: 30, endIndent: 30),
                  ),
                Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  color: entry.isCurrentUser
                      ? _primaryColor.withValues(alpha: 0.1)
                      : Colors.white,
                  elevation: entry.isCurrentUser ? 5 : 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: entry.isCurrentUser
                        ? const BorderSide(color: _primaryColor, width: 2)
                        : BorderSide.none,
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: _getRankColor(entry.rank),
                      child: Text('${entry.rank}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14)),
                    ),
                    title: Text(entry.nickname,
                        style: TextStyle(
                            fontWeight: entry.isCurrentUser
                                ? FontWeight.bold
                                : FontWeight.w600)),
                    subtitle:
                        Text('${entry.city} • ${entry.totalSuccesses} succès'),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('${entry.rankingScore.toStringAsFixed(1)} pts',
                            style: const TextStyle(
                                color: _primaryColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 15)),
                        if (entry.isCurrentUser)
                          const Text('MOI',
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: _primaryColor)),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Color _getRankColor(int rank) {
    if (rank == 1) return const Color(0xFFFFD700); // Or
    if (rank == 2) return const Color(0xFFC0C0C0); // Argent
    if (rank == 3) return const Color(0xFFCD7F32); // Bronze
    return _primaryColor.withValues(alpha: 0.7);
  }
}

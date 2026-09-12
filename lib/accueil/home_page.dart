// 📁 lib/home_page.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';

import 'welcome_page.dart';
import 'app_shared.dart';
import 'accueil_tab.dart';
import '../salle_de_classe_tab/cours_entrainement_tab.dart';
import '../ia_pages/ambition_ia_tab.dart';
import '../tv_leaders/leadership_carriere_tab.dart';
import '../plus/plus_tab.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  int _currentIndex = 0;

  static const List<String> _defaultTitles = [
    'ACCUEIL',
    'COURS & ENTRAÎNEMENT',
    'AMBITION+ IA',
    'LEADERSHIP & CARRIÈRE',
    'PLUS',
  ];

  final List<String> _titles = List.of(_defaultTitles);
  final List<VoidCallback?> _backHandlers = List<VoidCallback?>.filled(5, null);

  // ---- État applicatif partagé (conservé depuis l'ancienne HomePage) ----
  String? userName;
  String? serie;
  String? lv2;
  bool isPremium = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initAll();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkDeviceIdOnAppResume();
      _performAutoSync();
    }
  }

  Future<void> _initAll() async {
    final prefs = await SharedPreferences.getInstance();
    userName = prefs.getString('nom') ?? prefs.getString('prenom') ?? 'Élève';
    serie = prefs.getString('serie') ?? 'A';
    lv2 = prefs.getString('lv2');
    isPremium = prefs.getBool('premium') ?? false;
    await _performAutoSync();
    if (mounted) setState(() => _loading = false);
  }

  // ---------------------------------------------------------------------
  // Sécurité : vérification device id / premium (logique conservée §27)
  // ---------------------------------------------------------------------
  Future<String> _getDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final info = await deviceInfo.androidInfo;
      return info.id;
    } else if (Platform.isIOS) {
      final info = await deviceInfo.iosInfo;
      return info.identifierForVendor ?? 'unknown_ios';
    }
    return 'unknown_device_id';
  }

  Future<void> _saveLocalPremium(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('premium', value);
    if (mounted) setState(() => isPremium = value);
  }

  void _showErrorPopup(String message) {
    if (!mounted) return;
    showDialog(
      barrierDismissible: false,
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Accès Refusé'),
        content: Text(message, textAlign: TextAlign.center),
        actions: [
          Center(
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                if (!isPremium) {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const WelcomePage()),
                    (route) => false,
                  );
                }
              },
              child: const Text('Fermer'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _checkDeviceIdOnAppResume() async {
    final prefs = await SharedPreferences.getInstance();
    final isPremiumLocal = prefs.getBool('premium') ?? false;
    final matricule = prefs.getString('matricule');
    if (!isPremiumLocal || matricule == null) return;

    final currentDeviceId = await _getDeviceId();
    final supabase = Supabase.instance.client;

    try {
      final result = await supabase
          .from('utilisateurs_premium')
          .select('appareil_id')
          .eq('matricule', matricule)
          .maybeSingle();

      if (result == null) {
        await _saveLocalPremium(false);
        _showErrorPopup(
            'Votre profil Premium est introuvable. Vous avez été déconnecté.');
        return;
      }

      final savedDeviceId = result['appareil_id'];
      if (savedDeviceId != null && savedDeviceId != currentDeviceId) {
        await _saveLocalPremium(false);
        _showErrorPopup(
          "Ce compte Premium est déjà utilisé sur un autre appareil.\n\n"
          "L'accès a été déconnecté sur ce téléphone pour protéger ce compte.",
        );
      }
    } catch (e) {
      debugPrint('Erreur vérification sécurité : $e');
    }
  }

  Future<void> _performAutoSync() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final matricule = prefs.getString('matricule');
      if (matricule == null) return;

      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity == ConnectivityResult.none) return;

      final statsBox = Hive.box('userStatsBox');
      for (var key in statsBox.keys) {
        final statMap = Map<String, dynamic>.from(statsBox.get(key));
        if (statMap['pendingSync'] == true) {
          await Supabase.instance.client
              .from('statistiques_utilisateur')
              .upsert({
            'matricule': matricule,
            'section_id': statMap['sectionId'],
            'matiere': statMap['matiere'],
            'score_questions': statMap['score_questions'],
            'total_tentatives': statMap['total_tentatives'],
            'erreurs': statMap['erreurs'],
            'moyenne': statMap['moyenne'],
          }, onConflict: 'matricule,section_id');

          statMap['pendingSync'] = false;
          await statsBox.put(key, statMap);
        }
      }
    } catch (e) {
      debugPrint('Sync Error: $e');
    }
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Déconnexion'),
        content: const Text(
          "Voulez-vous vraiment vous déconnecter ?\nVos statistiques seront sauvegardées (si Premium) et l'application sera réinitialisée.",
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Non')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Oui')),
        ],
      ),
    );

    if (confirmed != true) return;

    final start = DateTime.now();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: CircularProgressIndicator(color: kAppOrange)),
    );

    await _performAutoSync();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await Hive.box('userStatsBox').clear();
    isPremium = false;

    final elapsed = DateTime.now().difference(start);
    const minimumDelay = Duration(seconds: 5);
    final remaining =
        elapsed >= minimumDelay ? Duration.zero : minimumDelay - elapsed;
    await Future.delayed(remaining);

    if (!mounted) return;
    Navigator.of(context).pop();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const WelcomePage()),
      (route) => false,
    );
  }

  // ---------------------------------------------------------------------
  // Communication onglets -> AppBar principale
  // ---------------------------------------------------------------------
  void _updateTab(int index, {String? title, VoidCallback? onBack}) {
    if (title != null) _titles[index] = title;
    _backHandlers[index] = onBack;
    if (index == _currentIndex && mounted) setState(() {});
  }

  TabUpdateCallback _callbackFor(int index) {
    return ({String? title, VoidCallback? onBack}) =>
        _updateTab(index, title: title, onBack: onBack);
  }

  void _onTabTapped(int index) {
    if (index == _currentIndex) return;
    setState(() => _currentIndex = index);
  }

  void _onHorizontalSwipe(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < 200) return;
    final next = velocity < 0
        ? (_currentIndex + 1).clamp(0, 4)
        : (_currentIndex - 1).clamp(0, 4);
    if (next != _currentIndex) setState(() => _currentIndex = next);
  }

  Future<bool> _showExitConfirmation() async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("Quitter l'application"),
            content: const Text('Voulez-vous vraiment quitter AMBITION+BAC ?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('NON')),
              TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('OUI')),
            ],
          ),
        ) ??
        false;
  }

  // ---------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------
  PreferredSizeWidget _buildAppBar() {
    final onBack = _backHandlers[_currentIndex];
    return AppBar(
      backgroundColor: kAppOrange,
      centerTitle: true,
      elevation: 2,
      automaticallyImplyLeading: false,
      leading: onBack != null
          ? IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: onBack,
            )
          : null,
      title: Text(
        _titles[_currentIndex],
        style:
            const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
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
    );
  }

  BottomNavigationBarItem _navItem(IconData icon, int index) {
    final selected = index == _currentIndex;
    return BottomNavigationBarItem(
      icon: Icon(icon, size: selected ? 28 : 24),
      label: '',
    );
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      currentIndex: _currentIndex,
      onTap: _onTabTapped,
      type: BottomNavigationBarType.fixed,
      backgroundColor: kAppOrange,
      selectedItemColor: Colors.white,
      unselectedItemColor: Colors.white70,
      showSelectedLabels: false,
      showUnselectedLabels: false,
      items: [
        _navItem(Icons.home_rounded, 0),
        _navItem(Icons.menu_book_rounded, 1),
        _navItem(Icons.smart_toy_rounded, 2),
        _navItem(Icons.work_rounded, 3),
        _navItem(Icons.more_horiz_rounded, 4),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_currentIndex != 0) {
          final onBack = _backHandlers[_currentIndex];
          if (onBack != null) {
            onBack();
            return;
          }
          setState(() => _currentIndex = 0);
          return;
        }
        final onBack = _backHandlers[_currentIndex];
        if (onBack != null) {
          onBack();
          return;
        }

        final shouldExit = await _showExitConfirmation();
        if (shouldExit) SystemNavigator.pop();
      },
      child: Scaffold(
        appBar: _buildAppBar(),
        backgroundColor: Colors.grey.shade100,
        bottomNavigationBar: _buildBottomNav(),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: kAppOrange))
            : GestureDetector(
                onHorizontalDragEnd: _onHorizontalSwipe,
                child: IndexedStack(
                  index: _currentIndex,
                  children: [
                    AccueilTab(onUpdate: _callbackFor(0)),
                    CoursEntrainementTab(
                      onUpdate: _callbackFor(1),
                      serie: serie ?? 'A',
                      lv2: lv2,
                      isPremium: isPremium,
                    ),
                    AmbitionIaTab(
                      onUpdate: _callbackFor(2),
                      lv2: lv2,
                      serie: serie ?? 'A',
                    ),
                    LeadershipCarriereTab(onUpdate: _callbackFor(3)),
                    PlusTab(
                      onUpdate: _callbackFor(4),
                      onLogout: _handleLogout,
                      isPremium: isPremium,
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

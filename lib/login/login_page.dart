import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../accueil/home_page.dart';
import 'dart:async';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  // ---------- Contrôleurs ----------
  final TextEditingController _nomController = TextEditingController();
  final TextEditingController _prenomController = TextEditingController();
  final TextEditingController _contactController = TextEditingController();
  final TextEditingController _contactParentController =
      TextEditingController();
  final TextEditingController _matriculeController = TextEditingController();

  // ---------- Variables d'état ----------
  String? _selectedType; // 'apprenant', 'enseignant', 'visiteur'
  String? _selectedSerie;
  String? _selectedLv2;

  final List<String> _series = ['A', 'C', 'D'];
  final List<String> _lv2Options = ['Allemand', 'Espagnol'];
  final List<String> _userTypes = ['apprenant', 'enseignant', 'visiteur'];

  bool _loading = false;
  bool _isLoginMode = false; // false = inscription, true = connexion

  // Étape : 'initial' (choix connexion/inscription), 'form' (formulaire)
  String _step = 'initial';

  // ---------- Device ID ----------
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

  // ---------- Méthodes de validation ----------
  bool _isValidPhone(String value) {
    return RegExp(r'^(01|05|07)\d{8}$').hasMatch(value);
  }

  bool _isValidMatriculeApprenant(String value) {
    return RegExp(r'^(\d{8}[A-Z]|BA\d{7})$').hasMatch(value);
  }

  bool _isValidPasswordEnseignantVisiteur(String value) {
    return value.length == 6;
  }

  // ---------- Affiche le dialogue de choix initial ----------
  void _showChoiceDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Ambition+ Bac'),
        content: const Text('Avez-vous déjà un compte Ambition+ Bac ?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _step = 'form';
                _isLoginMode = true;
                _selectedType = null;
                _matriculeController.clear();
                _contactController.clear();
                _contactParentController.clear();
              });
            },
            child: const Text('Oui, je me connecte'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _step = 'form';
                _isLoginMode = false;
                _selectedType = null;
                _nomController.clear();
                _prenomController.clear();
                _contactController.clear();
                _contactParentController.clear();
                _matriculeController.clear();
                _selectedSerie = null;
                _selectedLv2 = null;
              });
            },
            child: const Text('Non, je m\'inscris'),
          ),
        ],
      ),
    );
  }

  // =====================================================================
  // 🔧 Synchronisation Supabase → Hive (après connexion réussie)
  //
  // Récupère les lignes `statistiques_utilisateur` du matricule et les
  // écrit dans `Hive.box('userStatsBox')` avec la clé = `section_id`.
  //
  // Règles :
  //   1. Ne JAMAIS écraser une entrée locale avec `pendingSync: true`.
  //   2. Les entrées serveur sont marquées `pendingSync: false`.
  //   3. Toute erreur est loguée mais ne bloque PAS la connexion.
  // =====================================================================
  Future<void> _syncStatsFromServer(String matricule) async {
    if (matricule.isEmpty) return;

    try {
      // Depuis supabase_flutter v2, .select() renvoie
      // List<dynamic> (jamais null).
      final List<dynamic> rows = await Supabase.instance.client
          .from('statistiques_utilisateur')
          .select()
          .eq('matricule', matricule);

      if (rows.isEmpty) {
        debugPrint('ℹ️ Sync serveur→local : aucune stat à récupérer.');
        return;
      }

      if (!Hive.isBoxOpen('userStatsBox')) {
        await Hive.openBox('userStatsBox');
      }
      final statsBox = Hive.box('userStatsBox');

      int written = 0;
      int skipped = 0;

      for (final row in rows) {
        final map = Map<String, dynamic>.from(row as Map);
        final sectionId = map['section_id'] as String?;
        if (sectionId == null) continue;

        // Ne pas écraser une entrée locale non encore poussée
        final existing = statsBox.get(sectionId);
        if (existing != null) {
          final existingMap = Map<String, dynamic>.from(existing as Map);
          if (existingMap['pendingSync'] == true) {
            skipped++;
            continue;
          }
        }

        await statsBox.put(sectionId, {
          'matricule': matricule,
          'sectionId': sectionId,
          'matiere': map['matiere'] ?? '',
          'score_questions': map['score_questions'] ?? 0,
          'total_tentatives': map['total_tentatives'] ?? 0,
          'erreurs': map['erreurs'] ?? 0,
          'moyenne': (map['moyenne'] ?? 0).toDouble(),
          'pendingSync': false,
        });
        written++;
      }

      debugPrint(
          '✅ Sync serveur→local : $written entrée(s) écrite(s), $skipped ignorée(s) (pendingSync).');
    } catch (e) {
      debugPrint('⚠️ Erreur sync serveur→local : $e');
      // On n'interrompt pas la connexion si la sync échoue.
    }
  }

  // ------------------- CONNEXION -------------------
  Future<void> _login() async {
    final String? type = _selectedType;
    if (type == null) {
      _showErrorDialog("Veuillez choisir votre type d'utilisateur.");
      return;
    }

    if (type == 'apprenant') {
      // Connexion apprenant : matricule + contact personnel + contact parent
      if (_matriculeController.text.isEmpty) {
        _showErrorDialog("Veuillez saisir votre matricule.");
        return;
      }
      if (!_isValidMatriculeApprenant(_matriculeController.text)) {
        _showErrorDialog(
            "Matricule incorrect, veuillez entrer un matricule valide.");
        return;
      }
      if (_contactController.text.isEmpty) {
        _showErrorDialog("Veuillez saisir votre contact personnel.");
        return;
      }
      if (!_isValidPhone(_contactController.text)) {
        _showErrorDialog(
            "Contact incorrect, veuillez entrer un contact valide.");
        return;
      }
      if (_contactParentController.text.isEmpty) {
        _showErrorDialog("Veuillez saisir le contact de vos parents.");
        return;
      }
      if (!_isValidPhone(_contactParentController.text)) {
        _showErrorDialog(
            "Contact parent incorrect, veuillez entrer un contact valide.");
        return;
      }

      setState(() => _loading = true);
      try {
        final response = await Supabase.instance.client
            .from('utilisateurs_premium')
            .select()
            .eq('matricule', _matriculeController.text)
            .eq('contact_personnel', _contactController.text)
            .eq('contact_parent', _contactParentController.text)
            .eq('type_user', 'apprenant')
            .maybeSingle();

        if (response == null) {
          _showErrorDialog("Aucun compte trouvé avec ces identifiants.");
          setState(() => _loading = false);
          return;
        }

        // --- Contrôle d'appareil (anti-partage) ---
        if (!await _checkAndUpdateDevice(response)) {
          setState(() => _loading = false);
          return;
        }

        await _saveUserData(response);

        // 🔧 NOUVEAU : sync stats Supabase → Hive
        await _syncStatsFromServer(response['matricule'] ?? '');

        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const HomePage()),
            (Route<dynamic> route) => false,
          );
        }
      } catch (e) {
        debugPrint('Erreur login apprenant : $e');
        _showErrorDialog("Erreur lors de la connexion.");
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    } else {
      // Connexion enseignant ou visiteur : mot de passe + contact personnel
      if (_matriculeController.text.isEmpty) {
        _showErrorDialog("Veuillez saisir votre mot de passe.");
        return;
      }
      if (!_isValidPasswordEnseignantVisiteur(_matriculeController.text)) {
        _showErrorDialog(
            "Mot de passe incorrect, veuillez entrer un mot de passe valide.");
        return;
      }
      if (_contactController.text.isEmpty) {
        _showErrorDialog("Veuillez saisir votre contact personnel.");
        return;
      }
      if (!_isValidPhone(_contactController.text)) {
        _showErrorDialog(
            "Contact incorrect, veuillez entrer un contact valide.");
        return;
      }

      setState(() => _loading = true);
      try {
        final response = await Supabase.instance.client
            .from('utilisateurs_premium')
            .select()
            .eq('matricule', _matriculeController.text)
            .eq('contact_personnel', _contactController.text)
            .eq('type_user', type)
            .maybeSingle();

        if (response == null) {
          _showErrorDialog("Aucun compte trouvé avec ces identifiants.");
          setState(() => _loading = false);
          return;
        }

        // --- Contrôle d'appareil (anti-partage) ---
        if (!await _checkAndUpdateDevice(response)) {
          setState(() => _loading = false);
          return;
        }

        await _saveUserData(response);

        // 🔧 NOUVEAU : sync stats Supabase → Hive
        await _syncStatsFromServer(response['matricule'] ?? '');

        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const HomePage()),
            (Route<dynamic> route) => false,
          );
        }
      } catch (e) {
        debugPrint('Erreur login enseignant/visiteur : $e');
        _showErrorDialog("Erreur lors de la connexion.");
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }
  }

  // Vérification et mise à jour de l'appareil
  Future<bool> _checkAndUpdateDevice(Map<String, dynamic> userData) async {
    try {
      final currentDeviceId = await _getDeviceId();
      final savedDeviceId = userData['appareil_id'];

      if (savedDeviceId != null && savedDeviceId != currentDeviceId) {
        _showErrorDialog("Ce compte est déjà associé à un autre appareil. "
            "Contactez le support si vous avez changé d'appareil.");
        return false;
      }

      if (savedDeviceId == null) {
        // Associer l'appareil actuel au compte
        await Supabase.instance.client
            .from('utilisateurs_premium')
            .update({'appareil_id': currentDeviceId}).eq(
                'matricule', _matriculeController.text);
      }
      return true;
    } catch (e) {
      _showErrorDialog("Erreur lors de la vérification de l'appareil.");
      return false;
    }
  }

  // Sauvegarde des données utilisateur dans SharedPreferences
  Future<void> _saveUserData(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('nom', data['nom'] ?? '');
    await prefs.setString('prenom', data['prenom'] ?? '');
    await prefs.setString('serie', data['serie'] ?? '');
    await prefs.setString('lv2', data['lv2'] ?? '');
    await prefs.setString('matricule', data['matricule'] ?? '');
    await prefs.setString('type_user', data['type_user'] ?? '');
    await prefs.setString('contact_personnel', data['contact_personnel'] ?? '');
    await prefs.setString('contact_parent', data['contact_parent'] ?? '');
    await prefs.setBool('premium', data['premium'] ?? false);
  }

  // ------------------- INSCRIPTION -------------------
  Future<void> _register() async {
    final String? type = _selectedType;
    if (type == null) {
      _showErrorDialog("Veuillez choisir votre type d'utilisateur.");
      return;
    }

    // Champs communs
    if (_nomController.text.isEmpty || _prenomController.text.isEmpty) {
      _showErrorDialog("Veuillez saisir votre nom et prénom.");
      return;
    }
    if (_contactController.text.isEmpty) {
      _showErrorDialog("Veuillez saisir votre contact personnel.");
      return;
    }
    if (!_isValidPhone(_contactController.text)) {
      _showErrorDialog("Contact incorrect, veuillez entrer un contact valide.");
      return;
    }
    if (_selectedSerie == null) {
      _showErrorDialog("Veuillez choisir votre série.");
      return;
    }
    if (_selectedSerie == 'A' && _selectedLv2 == null) {
      _showErrorDialog("Veuillez choisir votre LV2.");
      return;
    }

    if (type == 'apprenant') {
      // Inscription apprenant
      if (_contactParentController.text.isEmpty) {
        _showErrorDialog("Veuillez saisir le contact de vos parents.");
        return;
      }
      if (!_isValidPhone(_contactParentController.text)) {
        _showErrorDialog(
            "Contact parent incorrect, veuillez entrer un contact valide.");
        return;
      }
      if (_matriculeController.text.isEmpty) {
        _showErrorDialog("Veuillez saisir votre matricule.");
        return;
      }
      if (!_isValidMatriculeApprenant(_matriculeController.text)) {
        _showErrorDialog(
            "Matricule incorrect, veuillez entrer un matricule valide.");
        return;
      }
    } else {
      // Inscription enseignant ou visiteur
      if (_matriculeController.text.isEmpty) {
        _showErrorDialog("Veuillez saisir un mot de passe de 6 caractères.");
        return;
      }
      if (!_isValidPasswordEnseignantVisiteur(_matriculeController.text)) {
        _showErrorDialog(
            "Mot de passe incorrect, veuillez entrer un mot de passe de 6 caractères.");
        return;
      }
    }

    setState(() => _loading = true);
    try {
      final existing = await Supabase.instance.client
          .from('utilisateurs_premium')
          .select('matricule')
          .eq('matricule', _matriculeController.text)
          .maybeSingle();

      if (existing != null) {
        _showErrorDialog(
            "Ce matricule/mot de passe est déjà utilisé. Veuillez en choisir un autre.");
        setState(() => _loading = false);
        return;
      }
    } catch (e) {
      _showErrorDialog("Erreur lors de la vérification du matricule.");
      setState(() => _loading = false);
      return;
    }

    // Dialogue d'essai premium (20 secondes)
    bool? result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _TrialDialog(serie: _selectedSerie ?? 'A'),
    );

    if (result != true) {
      setState(() => _loading = false);
      return;
    }

    // Construction des données
    final Map<String, dynamic> userData = {
      'nom': _nomController.text,
      'prenom': _prenomController.text,
      'serie': _selectedSerie,
      'lv2': (_selectedSerie == 'A') ? _selectedLv2 : null,
      'contact_personnel': _contactController.text,
      'contact_parent':
          (type == 'apprenant') ? _contactParentController.text : null,
      'matricule': _matriculeController.text,
      'type_user': type,
      'premium': false,
      'date_inscription': DateTime.now().toIso8601String(),
    };

    try {
      await Supabase.instance.client
          .from('utilisateurs_premium')
          .insert(userData);
    } catch (e) {
      _showErrorDialog("Erreur lors de l'inscription : $e");
      setState(() => _loading = false);
      return;
    }

    // Sauvegarder les infos en local
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('nom', _nomController.text);
    await prefs.setString('prenom', _prenomController.text);
    await prefs.setString('serie', _selectedSerie!);
    await prefs.setString('lv2', (_selectedSerie == 'A') ? _selectedLv2! : '');
    await prefs.setString('matricule', _matriculeController.text);
    await prefs.setString('type_user', type);
    await prefs.setString('contact_personnel', _contactController.text);
    await prefs.setString('contact_parent',
        (type == 'apprenant') ? _contactParentController.text : '');
    await prefs.setBool('premium', false);

    // ⚠️ Pas de sync stats : nouvel utilisateur, aucune stat côté serveur.
    //    (La box Hive sera créée/vidée par HomePage à l'init.)

    setState(() => _loading = false);
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const HomePage()),
        (Route<dynamic> route) => false,
      );
    }
  }

  // ------------------- AFFICHAGE DES ERREURS -------------------
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: Container(
          padding: const EdgeInsets.all(12),
          color: Colors.red,
          child: const Center(
            child: Icon(Icons.error, color: Colors.white, size: 40),
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Erreur de validation",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
        actions: [
          Center(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF007BFF),
              ),
              onPressed: () => Navigator.pop(context),
              child:
                  const Text("Fermer", style: TextStyle(color: Colors.white)),
            ),
          )
        ],
      ),
    );
  }

  // ---------- BUILD ----------
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_step == 'initial') {
        _showChoiceDialog();
      }
    });

    return Scaffold(
      backgroundColor: const Color(0xFFFFF4F0),
      body: SafeArea(
        child: Stack(
          children: [
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
            if (_step == 'form')
              SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                child: Column(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: double.infinity,
                          height: size.height * 0.08,
                          decoration: const BoxDecoration(
                            color: Color(0xFFFF8C00),
                            borderRadius: BorderRadius.only(
                              bottomLeft: Radius.circular(40),
                              bottomRight: Radius.circular(40),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: -40,
                          child: CircleAvatar(
                            radius: 40,
                            backgroundColor: Colors.white,
                            child: Padding(
                              padding: const EdgeInsets.all(4.0),
                              child: ClipOval(
                                child: Image.asset(
                                  'assets/images/outils/logo_ambitionbac.png',
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 80),
                    Text(
                      _isLoginMode ? "Connexion" : "Inscription",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 28,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isLoginMode
                          ? "Entre tes identifiants pour te connecter."
                          : "Remplis tes informations pour commencer l'aventure.",
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14, color: Colors.black),
                    ),
                    const SizedBox(height: 24),
                    _buildDropdown(
                      label: "Type d'utilisateur",
                      value: _selectedType,
                      items: _userTypes,
                      onChanged: (val) => setState(() {
                        _selectedType = val;
                        _selectedSerie = null;
                        _selectedLv2 = null;
                        _matriculeController.clear();
                        _contactController.clear();
                        _contactParentController.clear();
                      }),
                    ),
                    const SizedBox(height: 10),

                    // Formulaire commun (nom, prénom, contact) pour l'inscription
                    if (!_isLoginMode) ...[
                      _buildTextField(_nomController, "Nom"),
                      _buildTextField(_prenomController, "Prénom(s)"),
                      _buildTextField(_contactController, "Contact personnel"),
                    ],

                    // Série et LV2 (inscription uniquement)
                    if (!_isLoginMode) ...[
                      _buildDropdown(
                        label: "Série",
                        value: _selectedSerie,
                        items: _series,
                        onChanged: (val) {
                          setState(() {
                            _selectedSerie = val;
                            _selectedLv2 = null;
                          });
                        },
                      ),
                      if (_selectedSerie == 'A')
                        _buildDropdown(
                          label: "Langue vivante 2 (LV2)",
                          value: _selectedLv2,
                          items: _lv2Options,
                          onChanged: (val) =>
                              setState(() => _selectedLv2 = val),
                        ),
                    ],

                    // Champs spécifiques selon le mode et le type
                    if (_isLoginMode) ...[
                      if (_selectedType == 'apprenant') ...[
                        _buildTextField(
                          _matriculeController,
                          "Matricule (8 chiffres + 1 lettre ou BA + 7 chiffres)",
                        ),
                        _buildTextField(
                          _contactController,
                          "Contact personnel",
                        ),
                        _buildTextField(
                          _contactParentController,
                          "Contact parent",
                        ),
                      ],
                      if (_selectedType == 'enseignant' ||
                          _selectedType == 'visiteur') ...[
                        _buildTextField(
                          _matriculeController,
                          "Mot de passe (6 caractères)",
                        ),
                        _buildTextField(
                          _contactController,
                          "Contact personnel",
                        ),
                      ],
                    ] else ...[
                      if (_selectedType == 'apprenant') ...[
                        _buildTextField(
                          _contactParentController,
                          "Contact parent",
                        ),
                        _buildTextField(
                          _matriculeController,
                          "Matricule (8 chiffres + 1 lettre ou BA + 7 chiffres)",
                        ),
                      ],
                      if (_selectedType == 'enseignant' ||
                          _selectedType == 'visiteur') ...[
                        _buildTextField(
                          _matriculeController,
                          "Mot de passe (6 caractères)",
                        ),
                      ],
                    ],

                    const SizedBox(height: 32),
                    _buildButton(
                      label: _isLoginMode ? "SE CONNECTER" : "S'INSCRIRE",
                      color: _isLoginMode
                          ? Colors.blue.shade800
                          : Colors.green.shade800,
                      onPressed:
                          _loading ? null : (_isLoginMode ? _login : _register),
                      loading: _loading,
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---------- WIDGETS UTILITAIRES ----------
  Widget _buildTextField(TextEditingController controller, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          filled: true,
          fillColor: Colors.white,
        ),
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required Function(String?) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: DropdownButtonFormField<String>(
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          filled: true,
          fillColor: Colors.white,
        ),
        value: value,
        onChanged: onChanged,
        items: items
            .map((item) => DropdownMenuItem(
                  value: item,
                  child: Text(item),
                ))
            .toList(),
      ),
    );
  }

  Widget _buildButton({
    required String label,
    required Color color,
    required VoidCallback? onPressed,
    bool loading = false,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          shadowColor: Colors.black54,
          elevation: 3,
        ),
        child: loading
            ? const CircularProgressIndicator(color: Colors.white)
            : Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
      ),
    );
  }
}

// ==================== DIALOGUE DE PRÉSENTATION (20 SECONDES) ====================
// (inchangé)
class _TrialDialog extends StatefulWidget {
  final String serie;
  const _TrialDialog({required this.serie});

  @override
  State<_TrialDialog> createState() => _TrialDialogState();
}

class _TrialDialogState extends State<_TrialDialog> {
  bool _okVisible = false;
  int _secondsLeft = 20;
  Timer? _timer;

  bool _prixLoading = true;
  String? _displayText;

  @override
  void initState() {
    super.initState();
    _startTimer();
    _loadPrix();
  }

  Future<void> _loadPrix() async {
    try {
      final category = widget.serie == 'A' ? 'A' : 'other';
      final response = await Supabase.instance.client
          .from('prix_premium')
          .select('display_text')
          .eq('serie_category', category)
          .maybeSingle();

      if (response != null && response['display_text'] != null) {
        setState(() {
          _displayText = response['display_text'];
          _prixLoading = false;
        });
      } else {
        setState(() => _prixLoading = false);
      }
    } catch (e) {
      setState(() => _prixLoading = false);
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft > 0) {
        setState(() => _secondsLeft--);
      } else {
        _timer?.cancel();
        setState(() => _okVisible = true);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _displayPrice {
    if (_displayText != null) return _displayText!;
    return widget.serie == 'A'
        ? '3500 FCFA au lieu de 10000 FCFA'
        : '4200 FCFA au lieu de 15000 FCFA';
  }

  @override
  Widget build(BuildContext context) {
    Widget priceWidget;
    if (_prixLoading) {
      priceWidget = const SizedBox(
        height: 20,
        width: 20,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
      );
    } else {
      priceWidget = Text(
        "Paiement unique 12 mois : $_displayPrice",
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Color(0xFFFF8C00),
          fontSize: 16,
        ),
      );
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFF8C00), Color(0xFF006400)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 20,
              offset: Offset(0, 8),
            )
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Row(
              children: [
                Icon(Icons.emoji_events, color: Colors.white, size: 28),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Bienvenue dans Ambition+",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                "Tu es actuellement en mode GRATUIT.\n"
                "Tu auras accès à quelques leçons pour tester l'application.",
                style:
                    TextStyle(color: Colors.white, fontSize: 14, height: 1.5),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              "🌟 Passe au Premium et débloque :",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("• Tous les sujets et corrigés (2000 → 2026)",
                      style: TextStyle(color: Colors.white, fontSize: 13)),
                  Text("• Vidéos explicatives pour remise à niveau",
                      style: TextStyle(color: Colors.white, fontSize: 13)),
                  Text("• Laboratoires virtuels (biologie, chimie)",
                      style: TextStyle(color: Colors.white, fontSize: 13)),
                  Text("• IA spéciale pour les rédactions ivoiriennes",
                      style: TextStyle(color: Colors.white, fontSize: 13)),
                  Text(
                      "• Des milliers de quiz avec classements local, régional, national",
                      style: TextStyle(color: Colors.white, fontSize: 13)),
                  Text(
                      "• Récompenses pour les 15 meilleurs candidats en fin d'année",
                      style: TextStyle(color: Colors.white, fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
              ),
              child: priceWidget,
            ),
            const SizedBox(height: 20),
            if (!_okVisible)
              Column(
                children: [
                  const Text(
                    "Veuillez patienter...",
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        height: 60,
                        width: 60,
                        child: CircularProgressIndicator(
                          value: _secondsLeft / 20,
                          backgroundColor: Colors.white24,
                          valueColor:
                              const AlwaysStoppedAnimation<Color>(Colors.white),
                          strokeWidth: 5,
                        ),
                      ),
                      Text(
                        "$_secondsLeft",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
              )
            else
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFFFF8C00),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                child: const Text(
                  "OK, je commence !",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
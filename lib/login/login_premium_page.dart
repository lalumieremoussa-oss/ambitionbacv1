import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../accueil/home_page.dart';

class LoginPremiumPage extends StatefulWidget {
  const LoginPremiumPage({super.key});

  @override
  State<LoginPremiumPage> createState() => _LoginPremiumPageState();
}

class _LoginPremiumPageState extends State<LoginPremiumPage> {
  // Contrôleurs
  final TextEditingController _matricule = TextEditingController();
  final TextEditingController _contactPersonnel = TextEditingController();
  final TextEditingController _contactParent = TextEditingController();

  // Type d'utilisateur (uniquement pour l'interface)
  String? _selectedType; // 'apprenant', 'enseignant', 'visiteur'
  final List<String> _userTypes = ['apprenant', 'enseignant', 'visiteur'];

  bool _loading = false;

  // ---------- Device ID (anti‑partage) ----------
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

  // ---------- Validations ----------
  bool _isValidPhone(String value) {
    return RegExp(r'^(01|05|07)\d{8}$').hasMatch(value);
  }

  bool _isValidMatriculeApprenant(String value) {
    return RegExp(r'^(\d{8}[A-Z]|BA\d{7})$').hasMatch(value);
  }

  bool _isValidPasswordEnseignantVisiteur(String value) {
    return value.length == 6;
  }

  bool _validateInputs() {
    // Type obligatoire pour l'interface
    if (_selectedType == null) {
      _showErrorPopup("Veuillez choisir votre type d'utilisateur.");
      return false;
    }

    // Champs communs : contact personnel toujours requis
    final contact = _contactPersonnel.text.trim();
    if (contact.isEmpty) {
      _showErrorPopup("Veuillez saisir votre contact personnel.");
      return false;
    }
    if (!_isValidPhone(contact)) {
      _showErrorPopup("Contact incorrect, veuillez entrer un contact valide.");
      return false;
    }

    if (_selectedType == 'apprenant') {
      // ---------- Apprenant ----------
      final matricule = _matricule.text.trim();
      if (matricule.isEmpty) {
        _showErrorPopup("Veuillez saisir votre matricule.");
        return false;
      }
      if (!_isValidMatriculeApprenant(matricule)) {
        _showErrorPopup(
            "Matricule incorrect, veuillez entrer un matricule valide.");
        return false;
      }

      final parent = _contactParent.text.trim();
      if (parent.isEmpty) {
        _showErrorPopup("Veuillez saisir le contact de vos parents.");
        return false;
      }
      if (!_isValidPhone(parent)) {
        _showErrorPopup(
            "Contact parent incorrect, veuillez entrer un contact valide.");
        return false;
      }
    } else {
      // ---------- Enseignant / Visiteur ----------
      final password = _matricule.text.trim();
      if (password.isEmpty) {
        _showErrorPopup("Veuillez saisir votre mot de passe.");
        return false;
      }
      if (!_isValidPasswordEnseignantVisiteur(password)) {
        _showErrorPopup(
            "Mot de passe incorrect, veuillez entrer un mot de passe de 6 caractères.");
        return false;
      }
      _contactParent.text = '';
    }

    return true;
  }

  Future<void> _syncStatsFromServer(String matricule) async {
    if (matricule.isEmpty) return;

    try {
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
    }
  }

  // ---------- Connexion ----------
  Future<void> _seConnecter() async {
    if (!_validateInputs()) return;

    setState(() => _loading = true);

    try {
      final supabase = Supabase.instance.client;

      // Construction de la requête selon le type
      var query = supabase
          .from('utilisateurs_premium')
          .select()
          .eq('matricule', _matricule.text.trim())
          .eq('contact_personnel', _contactPersonnel.text.trim())
          .eq('premium', true); // ⚠️ Obligation d'être Premium

      // Pour les apprenants, on ajoute le contact_parent
      if (_selectedType == 'apprenant') {
        query = query.eq('contact_parent', _contactParent.text.trim());
      }

      final response = await query.maybeSingle();

      if (response == null) {
        _showErrorPopup("Aucun compte Premium trouvé avec ces informations. "
            "Vérifiez vos identifiants ou contactez le support si votre paiement est en cours.");
        setState(() => _loading = false);
        return;
      }

      // Vérification de l'appareil (sécurité anti‑partage)
      final currentDeviceId = await _getDeviceId();
      final savedDeviceId = response['appareil_id'];

      if (savedDeviceId != null && savedDeviceId != currentDeviceId) {
        _showErrorPopup(
            "Ce compte Premium est déjà associé à un autre appareil. "
            "Pour des raisons de sécurité, la connexion est refusée. "
            "Contactez le support si vous avez changé d'appareil.");
        setState(() => _loading = false);
        return;
      }

      // Si aucun appareil n'est enregistré, on l'associe maintenant
      if (savedDeviceId == null) {
        await supabase
            .from('utilisateurs_premium')
            .update({'appareil_id': currentDeviceId}).eq(
                'matricule', _matricule.text.trim());
      }

      // Sauvegarde des données utilisateur en local
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('premium', true);
      await prefs.setString('matricule', response['matricule'] ?? '');
      await prefs.setString('nom', response['nom'] ?? '');
      await prefs.setString('prenom', response['prenom'] ?? '');
      await prefs.setString('surnom', response['surnom'] ?? '');
      await prefs.setString('ville', response['ville'] ?? '');
      await prefs.setString('region', response['region'] ?? '');
      await prefs.setString('serie', response['serie'] ?? '');
      await prefs.setString('lv2', response['lv2'] ?? '');
      await prefs.setString(
          'contact_personnel', response['contact_personnel'] ?? '');
      await prefs.setString('contact_parent', response['contact_parent'] ?? '');

      // 🔧 NOUVEAU : synchroniser les statistiques Supabase → Hive
      // avant d'aller sur HomePage (qui lira la box locale).
      await _syncStatsFromServer(response['matricule'] ?? '');

      if (!mounted) return;

      // Redirection vers HomePage
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomePage()),
        (route) => false,
      );
    } catch (e) {
      debugPrint('Erreur connexion premium : $e');
      _showErrorPopup("Erreur lors de la connexion.");
      setState(() => _loading = false);
    }
  }

  // ---------- Dialogue d'erreur ----------
  void _showErrorPopup(String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: Container(
          color: Colors.red,
          height: 70,
          child: const Center(
              child: Icon(Icons.close, color: Colors.white, size: 36)),
        ),
        content: Text(message, textAlign: TextAlign.center),
        actions: [
          Center(
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              child:
                  const Text("Fermer", style: TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- Build ----------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF4F0),
      appBar: AppBar(
        title: const Text("Connexion Premium",
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFFFF8C00),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.lock_person, color: Color(0xFFFF8C00), size: 70),
              const SizedBox(height: 16),
              const Text(
                "Connectez-vous à votre compte Premium",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                "Saisissez les informations utilisées lors de votre inscription.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade700),
              ),
              const SizedBox(height: 24),

              // Type d'utilisateur
              DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  labelText: "Type d'utilisateur",
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                value: _selectedType,
                items: _userTypes.map((type) {
                  return DropdownMenuItem(value: type, child: Text(type));
                }).toList(),
                onChanged: (val) => setState(() {
                  _selectedType = val;
                  _matricule.clear();
                  _contactPersonnel.clear();
                  _contactParent.clear();
                }),
              ),
              const SizedBox(height: 15),

              // Champs dynamiques selon le type
              if (_selectedType == 'apprenant') ...[
                TextField(
                  controller: _matricule,
                  decoration: InputDecoration(
                    labelText:
                        "Matricule (8 chiffres + 1 lettre ou BA + 7 chiffres)",
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: _contactPersonnel,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: "Contact personnel",
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: _contactParent,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: "Contact d'un parent",
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],

              if (_selectedType == 'enseignant' ||
                  _selectedType == 'visiteur') ...[
                TextField(
                  controller: _matricule,
                  decoration: InputDecoration(
                    labelText: "Mot de passe (6 caractères)",
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: _contactPersonnel,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: "Contact personnel",
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],

              const SizedBox(height: 30),

              // Bouton de connexion
              SizedBox(
                height: 55,
                child: ElevatedButton(
                  onPressed: _loading ? null : _seConnecter,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF8C00),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _loading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          "SE CONNECTER",
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _matricule.dispose();
    _contactPersonnel.dispose();
    _contactParent.dispose();
    super.dispose();
  }
}

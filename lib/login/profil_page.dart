import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfilPage extends StatefulWidget {
  const ProfilPage({super.key});

  @override
  State<ProfilPage> createState() => _ProfilPageState();
}

class _ProfilPageState extends State<ProfilPage> {
  final TextEditingController _nom = TextEditingController();
  final TextEditingController _prenom = TextEditingController();
  final TextEditingController _surnom = TextEditingController();
  final TextEditingController _tel = TextEditingController();
  final TextEditingController _matricule = TextEditingController();
  final TextEditingController _unlockMatricule = TextEditingController();

  String? _serie;
  String? _lv2;
  String? _ville;
  String? _region;
  String? _appareilId;

  /// 🔧 Type d'utilisateur lu depuis Supabase
  /// ('apprenant' | 'enseignant' | 'visiteur')
  String? _typeUser;

  /// 🔧 Toggle affichage du mot de passe (enseignant/visiteur)
  bool _obscurePassword = true;

  Map<String, dynamic> _villeData = {};
  List<String> _villes = [];

  bool _loading = true;
  bool _isModifying = false;
  bool _isUnlocked = false;

  /// Raccourci pratique
  bool get _isApprenant => _typeUser == 'apprenant';

  /// Libellé du champ selon le type
  String get _identityFieldLabel =>
      _isApprenant ? 'Numéro matricule' : 'Mot de passe';

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    setState(() => _loading = true);
    await _loadVilleData();
    await _loadProfile();
    setState(() => _loading = false);
  }

  Future<void> _loadVilleData() async {
    final String jsonText =
        await rootBundle.loadString('assets/ville/ville.json');
    final Map<String, dynamic> data = json.decode(jsonText);
    setState(() {
      _villeData = data;
      _villes = data.values.expand((v) => v as List).cast<String>().toList();
    });
  }

  String _getRegionByVille(String ville) {
    for (final region in _villeData.keys) {
      if ((_villeData[region] as List).contains(ville)) {
        return region;
      }
    }
    return "Région inconnue";
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final matricule = prefs.getString('matricule');
    if (matricule == null) return;

    try {
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('utilisateurs_premium')
          .select()
          .eq('matricule', matricule)
          .single();

      _nom.text = response['nom'] ?? '';
      _prenom.text = response['prenom'] ?? '';
      _surnom.text = response['surnom'] ?? '';
      _tel.text = response['contact_personnel'] ?? '';
      _matricule.text = response['matricule'] ?? '';
      _serie = response['serie'];
      _lv2 = response['lv2'];
      _ville = response['ville'];
      _region = response['region'];
      _appareilId = response['appareil_id'];

      // 🔧 Lecture du type d'utilisateur
      _typeUser = response['type_user'] as String?;
    } catch (e) {
      debugPrint("Erreur chargement profil : $e");
      _showErrorPopup(
          "Impossible de charger votre profil. Vérifiez votre connexion.");
    }
  }

  // ------------------- DÉVERROUILLAGE MODIFICATION -------------------
  void _tryUnlockModification() {
    // On adapte le libellé de la boîte de dialogue selon le type
    final prompt = _isApprenant
        ? "Saisissez votre matricule"
        : "Saisissez votre mot de passe";

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Déverrouiller la modification"),
        content: TextField(
          controller: _unlockMatricule,
          obscureText: !_isApprenant,
          decoration: InputDecoration(labelText: prompt),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Annuler"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              if (_unlockMatricule.text.trim() == _matricule.text.trim()) {
                setState(() {
                  _isUnlocked = true;
                  _obscurePassword = true; // on re-masque à l'ouverture
                });
                _unlockMatricule.clear();
              } else {
                _showErrorPopup(
                    "Identifiant incorrect. Vous n'êtes pas autorisé à modifier ce profil.");
              }
            },
            child: const Text("Confirmer"),
          ),
        ],
      ),
    );
  }

  // ------------------- VALIDATION -------------------
  bool _validate() {
    if (_nom.text.isEmpty ||
        _prenom.text.isEmpty ||
        _surnom.text.isEmpty ||
        _tel.text.isEmpty ||
        _matricule.text.isEmpty ||
        _ville == null) {
      _showErrorPopup("Veuillez remplir les champs obligatoires du profil.");
      return false;
    }
    if (!RegExp(r'^(01|05|07)\d{8}$').hasMatch(_tel.text)) {
      _showErrorPopup("Le numéro de téléphone saisi n'est pas correct.");
      return false;
    }

    // 🔧 Validation adaptée au type
    if (_isApprenant) {
      if (!RegExp(r'^(\d{8}[A-Z]|BA\d{7})$').hasMatch(_matricule.text)) {
        _showErrorPopup("Format de matricule invalide.");
        return false;
      }
    } else {
      if (_matricule.text.length != 6) {
        _showErrorPopup(
            "Le mot de passe doit contenir exactement 6 caractères.");
        return false;
      }
    }
    return true;
  }

  Future<void> _updateProfile() async {
    if (!_validate()) return;

    setState(() => _loading = true);
    _region = _getRegionByVille(_ville!);

    try {
      final supabase = Supabase.instance.client;
      final prefs = await SharedPreferences.getInstance();
      final currentMatricule = prefs.getString('matricule')!;

      await supabase
          .from('utilisateurs_premium')
          .update({
            'nom': _nom.text.trim(),
            'prenom': _prenom.text.trim(),
            'surnom': _surnom.text.trim(),
            'contact_personnel': _tel.text.trim(),
            // 🔧 On écrit toujours dans `matricule` :
            //   - apprenant  → le matricule
            //   - enseignant/visiteur → le mot de passe
            'matricule': _matricule.text.trim(),
            'ville': _ville,
            'region': _region,
            'date_modification': DateTime.now().toIso8601String(),
          })
          .eq('matricule', currentMatricule)
          .limit(1);

      await prefs.setString('matricule', _matricule.text.trim());

      setState(() {
        _isModifying = false;
        _isUnlocked = false;
        _obscurePassword = true;
      });

      _showSuccessDialog(
          "PROFIL MIS À JOUR ✅\nVos informations ont été enregistrées avec succès.");
    } catch (e) {
      _showErrorPopup("Erreur lors de la modification du profil : $e");
    }

    setState(() => _loading = false);
  }

  // ------------------- DIALOGS -------------------
  void _showSuccessDialog(String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Container(
          color: Colors.green,
          height: 80,
          child: const Center(
              child: Icon(Icons.check_circle, color: Colors.white, size: 50)),
        ),
        content: Text(message, textAlign: TextAlign.center),
        actions: [
          Center(
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              child: const Text("OK", style: TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

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

  // ------------------- UI HELPERS -------------------
  bool _isEditable(String fieldName) {
    if (!_isModifying || !_isUnlocked) return false;
    if (['serie', 'lv2'].contains(fieldName)) return false;
    return true;
  }

  Widget _readOnlyText(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: TextFormField(
        initialValue: value == null || value.isEmpty ? 'Non spécifié' : value,
        readOnly: true,
        style: TextStyle(color: Colors.grey.shade700),
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.grey.shade200,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          suffixIcon: const Icon(Icons.lock, size: 18),
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController ctrl,
    String fieldName, {
    TextInputType keyboard = TextInputType.text,
    bool obscure = false,
  }) {
    final bool editable = _isEditable(fieldName);

    // 🔧 Le champ est masqué uniquement s'il est obscur ET éditable
    final bool actuallyObscure = obscure && editable && _obscurePassword;

    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: TextField(
        controller: ctrl,
        keyboardType: keyboard,
        readOnly: !editable,
        obscureText: actuallyObscure,
        style: TextStyle(color: editable ? Colors.black : Colors.grey.shade700),
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: editable ? Colors.white : Colors.grey.shade200,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          // 🔧 Toggle œil (si password éditable) > cadenas (si verrouillé)
          suffixIcon: editable && obscure
              ? IconButton(
                  icon: Icon(_obscurePassword
                      ? Icons.visibility_off
                      : Icons.visibility),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                )
              : (editable ? null : const Icon(Icons.lock, size: 18)),
        ),
      ),
    );
  }

  Widget _dropdownVille() {
    final bool editable = _isEditable('ville');
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: DropdownButtonFormField<String>(
        decoration: InputDecoration(
          labelText: "Ville ou commune",
          filled: true,
          fillColor: editable ? Colors.white : Colors.grey.shade200,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          suffixIcon: editable ? null : const Icon(Icons.lock, size: 18),
        ),
        initialValue: _ville,
        items: _villes
            .map((v) => DropdownMenuItem(value: v, child: Text(v)))
            .toList(),
        onChanged: editable
            ? (val) => setState(() {
                  _ville = val;
                  _region = _getRegionByVille(val!);
                })
            : null,
      ),
    );
  }

  // ------------------- CONSTRUCTION DES CHAMPS -------------------
  Widget _buildFields() {
    // 🔧 Le label du champ identité dépend du type d'utilisateur
    final label = _identityFieldLabel;

    // --- Mode lecture seule (non déverrouillé) ---
    if (!_isUnlocked) {
      // Masquage adapté :
      //   - apprenant → 14 étoiles fixes
      //   - enseignant/visiteur → autant de • que de caractères saisis
      final String? maskedValue = _matricule.text.isEmpty
          ? null
          : (_isApprenant ? '**************' : '•' * _matricule.text.length);

      return Column(
        children: [
          _readOnlyText("Nom", _nom.text),
          _readOnlyText("Prénom(s)", _prenom.text),
          _readOnlyText("Nom de l'établissement", _surnom.text),
          _readOnlyText("Numéro téléphone", _tel.text),
          _readOnlyText(label, maskedValue),
          _readOnlyText("Série", _serie == null ? null : "Série $_serie"),
          if (_serie == "A") _readOnlyText("Langue vivante 2", _lv2),
          _readOnlyText("Ville ou commune", _ville),
        ],
      );
    }

    // --- Mode édition (déverrouillé) ---
    return Column(
      children: [
        _field("Nom", _nom, 'nom'),
        _field("Prénom(s)", _prenom, 'prenom'),
        _field("Nom de l'établissement", _surnom, 'surnom'),
        _field("Numéro téléphone", _tel, 'tel', keyboard: TextInputType.phone),
        // 🔧 Champ identité : matricule (apprenant) OU mot de passe (autres)
        _field(
          label,
          _matricule,
          'matricule',
          obscure: !_isApprenant,
        ),
        _readOnlyText("Série", _serie == null ? null : "Série $_serie"),
        if (_serie == "A") _readOnlyText("Langue vivante 2", _lv2),
        _dropdownVille(),
      ],
    );
  }

  // ------------------- BUILD -------------------
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: const Color(0xFFFFF4F0),
        appBar: AppBar(
          title: const Text("Chargement..."),
          backgroundColor: const Color(0xFFFF8C00),
        ),
        body: const Center(
            child: CircularProgressIndicator(color: Color(0xFFFF8C00))),
      );
    }

    // 🔧 Titre AppBar
    String appBarTitle = "Mon Profil Premium";
    if (_isModifying) {
      appBarTitle = _isUnlocked ? "Modifier le profil" : "Vérification requise";
    }

    // 🔧 Petit libellé de type affiché sous le statut
    final typeLabel = (_typeUser ?? 'apprenant').toUpperCase();

    return Scaffold(
      backgroundColor: const Color(0xFFFFF4F0),
      appBar: AppBar(
        title: Text(appBarTitle,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFFFF8C00),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            children: [
              const Icon(Icons.workspace_premium,
                  color: Color(0xFFFF8C00), size: 60),
              const Text("Statut : PREMIUM",
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFF8C00))),
              const SizedBox(height: 6),
              // 🔧 Affichage du type d'utilisateur
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: _isApprenant
                      ? Colors.green.shade100
                      : Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  "Type : $typeLabel",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _isApprenant
                        ? Colors.green.shade800
                        : Colors.blue.shade800,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text("Série : ${_serie ?? 'N/A'} - LV2 : ${_lv2 ?? 'N/A'}",
                  style: const TextStyle(fontSize: 15)),
              if (_appareilId != null && _isModifying)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text("ID Appareil : $_appareilId",
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ),
              const SizedBox(height: 24),
              _buildFields(),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: _loading
                      ? null
                      : () {
                          if (!_isModifying) {
                            setState(() => _isModifying = true);
                          } else if (!_isUnlocked) {
                            _tryUnlockModification();
                          } else {
                            _updateProfile();
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: !_isModifying
                        ? Colors.orange.shade700
                        : (_isUnlocked
                            ? Colors.blue.shade700
                            : Colors.orange.shade800),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    !_isModifying
                        ? "MODIFIER MES INFORMATIONS"
                        : (_isUnlocked
                            ? "SAUVEGARDER LES MODIFICATIONS"
                            : "DÉVERROUILLER LE FORMULAIRE"),
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              if (_isModifying)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: TextButton.icon(
                    icon: const Icon(Icons.cancel, color: Colors.red),
                    onPressed: () async {
                      setState(() {
                        _isModifying = false;
                        _isUnlocked = false;
                        _obscurePassword = true;
                      });
                      await _initData();
                    },
                    label: const Text("ANNULER",
                        style: TextStyle(
                            color: Colors.red, fontWeight: FontWeight.bold)),
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
    _nom.dispose();
    _prenom.dispose();
    _surnom.dispose();
    _tel.dispose();
    _matricule.dispose();
    _unlockMatricule.dispose();
    super.dispose();
  }
}

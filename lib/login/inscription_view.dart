import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class InscriptionView extends StatefulWidget {
  const InscriptionView({super.key});

  @override
  State<InscriptionView> createState() => _InscriptionViewState();
}

class _InscriptionViewState extends State<InscriptionView> {
  int _step = 0; // 0: série, 1: paiement, 2: formulaire, 3: envoi

  // ---- Contrôleurs ----
  final TextEditingController _matricule = TextEditingController();
  final TextEditingController _tel = TextEditingController();
  final TextEditingController _transactionRef = TextEditingController();

  String? _serie;
  String? _moyenPaiement; // 'MTN', 'Moov', 'Orange', 'Wave'
  String? _userType; // 'apprenant', 'enseignant', 'visiteur'

  bool _aPaye = false;
  bool _paymentProcessing = false;
  bool _envoiEnCours = false;
  bool _prixLoading = true;

  // Stockage des prix depuis Supabase
  Map<String, dynamic>? _prixData; // clé: 'A' ou 'other'

  static const String _whatsappNumero = "2250778854285";
  static const String _formspreeUrl = "https://formspree.io/f/mlgyoqzq";

  // Numéros par opérateur
  String get _numeroPaiement {
    switch (_moyenPaiement) {
      case 'MTN':
        return "0586923270";
      case 'Moov':
        return "0172200549";
      case 'Orange':
        return "0778854285";
      case 'Wave':
        return "0778854285";
      default:
        return "";
    }
  }

  // Montant dynamique depuis Supabase (avec fallback)
  String get _montant {
    if (_prixData == null) return "4200";
    final category = _serie == 'A' ? 'A' : 'other';
    final prix = _prixData![category];
    if (prix == null) return "4200";
    return prix['amount'].toString();
  }

  // ------------------- CHARGEMENT DES PRIX -------------------
  Future<void> _loadPrix() async {
    try {
      final response = await Supabase.instance.client
          .from('prix_premium')
          .select('serie_category, amount, display_text');

      final Map<String, dynamic> data = {};
      for (var item in response) {
        data[item['serie_category']] = {
          'amount': item['amount'],
          'display_text': item['display_text'],
        };
      }
      setState(() {
        _prixData = data;
        _prixLoading = false;
      });
    } catch (e) {
      debugPrint("Erreur chargement prix: $e");
      setState(() => _prixLoading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadPrix();
  }

  // ------------------- VALIDATION -------------------
  bool _validateContact(String value) {
    return RegExp(r'^(01|05|07)\d{8}$').hasMatch(value);
  }

  bool _validateMatriculeApprenant(String value) {
    return RegExp(r'^(\d{8}[A-Z]|BA\d{7})$').hasMatch(value);
  }

  bool _validatePasswordEnseignantVisiteur(String value) {
    return value.length == 6;
  }

  bool _validateForm() {
    if (_serie == null) {
      _showErrorPopup("Veuillez choisir votre série.");
      return false;
    }
    if (_userType == null) {
      _showErrorPopup("Veuillez choisir votre type d'utilisateur.");
      return false;
    }
    if (_matricule.text.trim().isEmpty) {
      _showErrorPopup(_userType == 'apprenant'
          ? "Veuillez saisir votre matricule."
          : "Veuillez saisir votre mot de passe.");
      return false;
    }
    // Validation selon le type
    if (_userType == 'apprenant') {
      if (!_validateMatriculeApprenant(_matricule.text.trim())) {
        _showErrorPopup(
            "Format de matricule invalide (ex: 12345678A ou BA1234567).");
        return false;
      }
    } else {
      if (!_validatePasswordEnseignantVisiteur(_matricule.text.trim())) {
        _showErrorPopup(
            "Le mot de passe doit comporter exactement 6 caractères.");
        return false;
      }
    }

    if (_tel.text.trim().isEmpty) {
      _showErrorPopup("Veuillez saisir votre contact personnel.");
      return false;
    }
    if (!_validateContact(_tel.text.trim())) {
      _showErrorPopup(
          "Le numéro de contact personnel n'est pas valide (ex: 0778854285).");
      return false;
    }
    if (_moyenPaiement == null) {
      _showErrorPopup("Veuillez choisir votre moyen de paiement.");
      return false;
    }
    if (_transactionRef.text.trim().isEmpty) {
      _showErrorPopup("Veuillez saisir la référence de la transaction.");
      return false;
    }
    return true;
  }

  // ------------------- MESSAGE -------------------
  String _buildMessage() {
    return "NOUVELLE INSCRIPTION PREMIUM - AMBITION+\n\n"
        "Type d'utilisateur : $_userType\n"
        "Série : $_serie\n"
        "${_userType == 'apprenant' ? 'Matricule' : 'Mot de passe'} : ${_matricule.text.trim()}\n"
        "Contact personnel : ${_tel.text.trim()}\n"
        "Moyen de paiement : $_moyenPaiement\n"
        "Montant payé : ${_montant} FCFA\n"
        "Référence de transaction : ${_transactionRef.text.trim()}";
  }

  // 🚀 ACTIONS
  Future<void> _sendViaWhatsApp() async {
    final message = _buildMessage();

    final whatsappUrl = Uri.https(
      'wa.me',
      '/$_whatsappNumero',
      {'text': message},
    );

    try {
      await launchUrl(whatsappUrl, mode: LaunchMode.externalApplication);
      _showInfoDialog(
        "📱 WhatsApp va s'ouvrir.\n\n"
        "Votre message a été pré-rempli. Envoyez-le simplement.",
      );
    } catch (e) {
      _showErrorPopup("Impossible d'ouvrir WhatsApp.\n"
          "Veuillez utiliser le bouton 'ADMINISTRATEURS'.");
    }
  }

  Future<void> _initiateWavePayment() async {
    setState(() => _paymentProcessing = true);

    final paymentUrl = Uri.parse(
        "https://pay.wave.com/m/M_ci_ob72nL0Q8iua/c/ci/?amount=${_montant}&currency=XOF");

    try {
      await launchUrl(paymentUrl, mode: LaunchMode.externalApplication);

      _showPaymentConfirmationDialog("💰 Paiement Wave\n\n"
          "Montant : ${_montant} FCFA\n\n"
          "✅ Effectuez le paiement sur l'application Wave.\n\n"
          "📝 Copiez la référence reçue par SMS.");
    } catch (e) {
      _showErrorPopup("Impossible de lancer Wave.\n\n"
          "Transférez manuellement au : $_numeroPaiement");
    }

    setState(() => _paymentProcessing = false);
  }

  Future<void> _sendToAdministrators() async {
    setState(() => _envoiEnCours = true);

    try {
      final response = await http.post(
        Uri.parse(_formspreeUrl),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'message': _buildMessage(),
          'type_user': _userType ?? '',
          'serie': _serie ?? '',
          'matricule': _matricule.text.trim(),
          'contact_personnel': _tel.text.trim(),
          'moyen_paiement': _moyenPaiement ?? '',
          'montant': "${_montant} FCFA",
          'reference_transaction': _transactionRef.text.trim(),
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 202) {
        if (mounted) {
          _showSuccessDialog(
              "Dossier envoyé avec succès.\nTraitement sous 1 heure environ.");
        }
      } else {
        _showErrorPopup("Envoi échoué (code ${response.statusCode}).");
      }
    } catch (e) {
      _showErrorPopup("Erreur : $e");
    }

    if (mounted) setState(() => _envoiEnCours = false);
  }

  // ------------------- DIALOGS -------------------
  void _showPaymentConfirmationDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text("Paiement"),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _aPaye = true);
              if (_aPaye) setState(() => _step = 2);
            },
            child: const Text("J'AI PAYÉ ✅"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _aPaye = false);
            },
            child: const Text("ANNULER"),
          ),
        ],
      ),
    );
  }

  void _showInfoDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text("Information"),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  void _showSuccessDialog(String message) {
    showDialog(
      barrierDismissible: false,
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Container(
          color: Colors.green,
          height: 80,
          child: const Center(
            child: Icon(Icons.check_circle, color: Colors.white, size: 50),
          ),
        ),
        content: Text(message, textAlign: TextAlign.center),
        actions: [
          Center(
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              child: const Text("OK", style: TextStyle(color: Colors.white)),
            ),
          )
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
            child: Icon(Icons.close, color: Colors.white, size: 36),
          ),
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

  // Navigation
  void _goToPaymentStep() {
    if (_serie == null) {
      _showErrorPopup("Veuillez choisir votre série.");
      return;
    }
    setState(() => _step = 1);
  }

  void _handlePaymentAnswer(bool paye) {
    setState(() => _aPaye = paye);
    if (paye) setState(() => _step = 2);
  }

  void _goToUploadStep() {
    if (!_validateForm()) return;
    setState(() => _step = 3);
  }

  void _showInstructionsPaiement(String operateur) {
    final numero = _numeroPaiement;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text("Paiement via $operateur"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("💳 Montant : ${_montant} FCFA"),
            const SizedBox(height: 8),
            Text("📱 Numéro : $numero"),
            const SizedBox(height: 8),
            Text(
              "1. Envoyez le montant requis via $operateur\n"
              "2. Copiez la référence reçue\n"
              "3. Revenez et cliquez sur 'J'AI PAYÉ'",
              style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("J'AI COMPRIS"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _aPaye = true);
              if (_aPaye) setState(() => _step = 2);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text("J'AI PAYÉ ✅"),
          ),
        ],
      ),
    );
  }

  // ------------------- UI ÉTAPES -------------------
  Widget _buildStepSerie() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text("Choisissez votre série",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 20),
        ...["A", "C", "D"].map((s) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor:
                      _serie == s ? const Color(0xFFFF8C00) : Colors.white,
                  side: const BorderSide(color: Color(0xFFFF8C00)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => setState(() => _serie = s),
                child: Text(
                  "Série $s",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _serie == s ? Colors.white : const Color(0xFFFF8C00),
                  ),
                ),
              ),
            )),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _goToPaymentStep,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green.shade700,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text("SUIVANT",
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _buildStepPaiement() {
    final moyens = [
      {"nom": "Wave", "icon": Icons.waves, "color": Colors.blue},
      {
        "nom": "MTN",
        "icon": Icons.phone_android,
        "color": Colors.yellow.shade800
      },
      {"nom": "Orange", "icon": Icons.phone_android, "color": Colors.orange},
      {"nom": "Moov", "icon": Icons.phone_android, "color": Colors.blueGrey},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text("Montant à payer : ${_montant} FCFA",
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center),
        const SizedBox(height: 8),
        const Text("Choisissez votre moyen de paiement",
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 2.2,
          children: moyens.map((m) {
            return OutlinedButton.icon(
              icon: Icon(m["icon"] as IconData, color: m["color"] as Color),
              label: Text(m["nom"] as String,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.black87)),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _paymentProcessing
                  ? null
                  : () {
                      setState(() => _moyenPaiement = m["nom"] as String);
                      if (_moyenPaiement == "Wave") {
                        _initiateWavePayment();
                      } else {
                        _showInstructionsPaiement(_moyenPaiement!);
                      }
                    },
            );
          }).toList(),
        ),
        if (_paymentProcessing)
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Center(
                child: CircularProgressIndicator(color: Color(0xFFFF8C00))),
          ),
        const SizedBox(height: 30),
        const Text("Avez-vous effectué le paiement ?",
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: () => _handlePaymentAnswer(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text("OUI",
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: () => _handlePaymentAnswer(false),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text("NON",
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
        if (!_aPaye)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              "Veuillez d'abord effectuer le paiement, puis revenez répondre \"OUI\".",
              style: TextStyle(color: Colors.red.shade700),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }

  Widget _buildStepFormulaire() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text("Complétez vos informations",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 20),

        // Type d'utilisateur
        DropdownButtonFormField<String>(
          decoration: InputDecoration(
            labelText: "Type d'utilisateur",
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          value: _userType,
          items: const [
            DropdownMenuItem(value: 'apprenant', child: Text('Apprenant')),
            DropdownMenuItem(value: 'enseignant', child: Text('Enseignant')),
            DropdownMenuItem(value: 'visiteur', child: Text('Visiteur')),
          ],
          onChanged: (val) => setState(() {
            _userType = val;
            _matricule.clear();
          }),
        ),
        const SizedBox(height: 14),

        // Champ matricule ou mot de passe selon le type
        _textField(
          _userType == 'apprenant'
              ? "Numéro matricule (ex: 12345678A ou BA1234567)"
              : "Mot de passe (6 caractères)",
          _matricule,
          keyboard: TextInputType.text,
        ),
        _textField("Contact personnel (ex: 0778854285)", _tel,
            keyboard: TextInputType.phone),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            children: [
              const Text("Moyen de paiement : ",
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text(_moyenPaiement ?? 'Non défini'),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _textField(
          "ID / Référence de la transaction (Requis)",
          _transactionRef,
          keyboard: TextInputType.text,
          highlighted: true,
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _goToUploadStep,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green.shade700,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text("CONTINUER",
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _textField(String label, TextEditingController ctrl,
      {TextInputType keyboard = TextInputType.text, bool highlighted = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: ctrl,
        keyboardType: keyboard,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
              color: highlighted ? const Color(0xFFFF8C00) : Colors.black87,
              fontWeight: highlighted ? FontWeight.bold : FontWeight.normal),
          filled: true,
          fillColor: Colors.white,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
                color: highlighted ? const Color(0xFFFF8C00) : Colors.grey,
                width: highlighted ? 2 : 1),
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  Widget _buildStepEnvoi() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text("Dernière étape",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        const Text(
          "Votre dossier inclut désormais votre référence de transaction.\n"
          "Choisissez UNE SEULE des deux méthodes ci-dessous.",
          style: TextStyle(color: Colors.black87, fontSize: 14),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline,
                  color: Color(0xFFFF8C00), size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Choisissez WhatsApp OU Administrateurs, pas les deux.",
                  style: TextStyle(
                      color: Colors.orange.shade900,
                      fontSize: 13,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 40),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.chat, color: Colors.white),
                label: const Text("WHATSAPP",
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  padding: const EdgeInsets.symmetric(vertical: 18),
                ),
                onPressed: _sendViaWhatsApp,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                icon: _envoiEnCours
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.send, color: Colors.white),
                label: Text(
                  _envoiEnCours ? "ENVOI..." : "ADMINISTRATEURS",
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueGrey.shade700,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                ),
                onPressed: _envoiEnCours ? null : _sendToAdministrators,
              ),
            ),
          ],
        ),
        const SizedBox(height: 35),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 6,
                    offset: const Offset(0, 3))
              ]),
          child: Column(
            children: [
              Text(
                "⚠️ DÉLAIS DE TRAITEMENT",
                style: TextStyle(
                    color: Colors.red.shade800,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                "• WhatsApp : traitement sous 5 minutes\n"
                "• Administrateurs : traitement sous 1 heure",
                style: TextStyle(
                    color: Colors.grey.shade800,
                    fontSize: 15,
                    height: 1.5,
                    fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ------------------- BUILD PRINCIPAL -------------------
  @override
  Widget build(BuildContext context) {
    if (_prixLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFFFF8C00)),
        ),
      );
    }

    Widget content;
    switch (_step) {
      case 0:
        content = _buildStepSerie();
        break;
      case 1:
        content = _buildStepPaiement();
        break;
      case 2:
        content = _buildStepFormulaire();
        break;
      default:
        content = _buildStepEnvoi();
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFFF4F0),
      appBar: AppBar(
        title: const Text("Inscription Premium",
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFFFF8C00),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            if (_step > 0) {
              setState(() => _step -= 1);
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: content,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _matricule.dispose();
    _tel.dispose();
    _transactionRef.dispose();
    super.dispose();
  }
}

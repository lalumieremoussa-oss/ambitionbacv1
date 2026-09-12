import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:device_info_plus/device_info_plus.dart';

import 'profil_page.dart';
import 'inscription_view.dart';
import 'login_premium_page.dart';

class VipPage extends StatefulWidget {
  const VipPage({super.key});

  @override
  State<VipPage> createState() => _VipPageState();
}

class _VipPageState extends State<VipPage> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _checkPremiumStatus();
  }

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

  Future<void> _checkPremiumStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final isPremiumLocal = prefs.getBool('premium') ?? false;
    final matricule = prefs.getString('matricule');

    if (isPremiumLocal && matricule != null && matricule.isNotEmpty) {
      try {
        final supabase = Supabase.instance.client;
        final response = await supabase
            .from('utilisateurs_premium')
            .select()
            .eq('matricule', matricule)
            .maybeSingle();

        if (response != null) {
          final currentDeviceId = await _getDeviceId();
          final savedDeviceId = response['appareil_id'];

          if (savedDeviceId == null || savedDeviceId == currentDeviceId) {
            // Compte Premium valide sur cet appareil -> Profil direct
            if (!mounted) return;
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const ProfilPage()),
            );
            return;
          } else {
            // Compte déjà utilisé sur un autre appareil -> on invalide localement
            await prefs.setBool('premium', false);
          }
        } else {
          // Le matricule local n'existe plus côté Supabase -> on invalide
          await prefs.setBool('premium', false);
        }
      } catch (e) {
        debugPrint("Erreur de vérification du statut Premium : $e");
        // En cas d'erreur réseau on laisse l'utilisateur sur l'écran de choix
        // plutôt que de bloquer sur un chargement infini.
      }
    }

    if (mounted) setState(() => _loading = false);
  }

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
          child: CircularProgressIndicator(color: Color(0xFFFF8C00)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFFF4F0),
      appBar: AppBar(
        title: const Text("Ambition+ Premium",
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFFFF8C00),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.workspace_premium,
                  color: Color(0xFFFF8C00), size: 90),
              const SizedBox(height: 20),
              const Text(
                "Passez à l'expérience Premium",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                "Accédez à tous les cours, quiz et exercices corrigés en illimité.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade700, fontSize: 15),
              ),
              const SizedBox(height: 40),

              // Payer maintenant
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.payment, color: Colors.white),
                  label: const Text(
                    "PAYER MAINTENANT",
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const InscriptionView()),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),

              // Déjà un compte premium
              SizedBox(
                width: double.infinity,
                height: 55,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.login, color: Color(0xFFFF8C00)),
                  label: const Text(
                    "J'AI DÉJÀ UN COMPTE PREMIUM",
                    style: TextStyle(
                        color: Color(0xFFFF8C00), fontWeight: FontWeight.bold),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFFF8C00), width: 2),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const LoginPremiumPage()),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 📁 lib/tabs/plus_tab.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../accueil/app_shared.dart';
import 'about.dart';
import 'administration_page.dart';
import '../login/vip_page.dart';
import 'classement_page.dart';
import 'statistiques_page.dart';
import 'messages_page.dart';

// -----------------------------------------------------------------------------
// 🎨 COULEURS
// -----------------------------------------------------------------------------

const Color _messagesRed = Color(0xFFE53935);

// -----------------------------------------------------------------------------
// 📦 PLUS TAB
// -----------------------------------------------------------------------------

class PlusTab extends StatefulWidget {
  final TabUpdateCallback onUpdate;
  final VoidCallback onLogout;
  final bool isPremium;

  const PlusTab({
    super.key,
    required this.onUpdate,
    required this.onLogout,
    required this.isPremium,
  });

  @override
  State<PlusTab> createState() => _PlusTabState();
}

// -----------------------------------------------------------------------------
// MENU ITEM
// -----------------------------------------------------------------------------

class _MenuItem {
  final String titre;
  final IconData icone;
  final Color couleur;
  final VoidCallback onTap;
  final int badge;

  _MenuItem({
    required this.titre,
    required this.icone,
    required this.couleur,
    required this.onTap,
    this.badge = 0,
  });
}

// -----------------------------------------------------------------------------
// STATE
// -----------------------------------------------------------------------------

class _PlusTabState extends State<PlusTab> {
  int _unreadMessages = 0;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onUpdate(
        title: 'PLUS',
        onBack: null,
      );

      // ---------------------------------------------------------
      // CHARGEMENT EN ARRIÈRE-PLAN
      // ---------------------------------------------------------

      _preloadMessages();
    });
  }

  // ---------------------------------------------------------------------------
  // PRÉCHARGEMENT MESSAGES
  // ---------------------------------------------------------------------------

  Future<void> _preloadMessages() async {
    try {
      final supabase = Supabase.instance.client;

      // ---------------------------------------------------------
      // CHARGER TOUS LES MESSAGES SUPABASE
      // ---------------------------------------------------------

      final response = await supabase
          .from('messages')
          .select(
            'id, title, content, date, status, icon',
          )
          .order(
            'date',
            ascending: false,
          );

      final allMessages = (response as List)
          .map(
            (json) => Message.fromJson(
              Map<String, dynamic>.from(
                json,
              ),
            ),
          )
          .toList();

      // ---------------------------------------------------------
      // FILTRAGE SELON LE TYPE D'UTILISATEUR
      // ---------------------------------------------------------

      final visibleMessages = allMessages.where((message) {
        switch (message.status) {
          case 'ALL':
            return true;

          case 'PREMIUM':
            return widget.isPremium;

          case 'FREE':
            return !widget.isPremium;

          default:
            return false;
        }
      }).toList();

      // ---------------------------------------------------------
      // SAUVEGARDE HIVE
      // ---------------------------------------------------------

      await MessageHiveService.saveMessages(
        visibleMessages,
      );

      // ---------------------------------------------------------
      // CALCUL NON LUS
      // ---------------------------------------------------------

      final unread = MessageHiveService.getUnreadCount();

      if (!mounted) return;

      setState(() {
        _unreadMessages = unread;
      });
    } catch (e) {
      debugPrint(
        'Erreur préchargement messages : $e',
      );

      // ---------------------------------------------------------
      // SI SUPABASE ÉCHOUE :
      // ON UTILISE CE QUI EST DÉJÀ DANS HIVE
      // ---------------------------------------------------------

      if (!mounted) return;

      setState(() {
        _unreadMessages = MessageHiveService.getUnreadCount();
      });
    }
  }

  // ---------------------------------------------------------------------------
  // NAVIGATION
  // ---------------------------------------------------------------------------

  void _push(Widget page) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => page,
      ),
    ).then((_) {
      // Après retour de MessagesPage,
      // recalculer le badge.
      _refreshUnreadCount();
    });
  }

  // ---------------------------------------------------------------------------
  // RAFRAÎCHIR BADGE
  // ---------------------------------------------------------------------------

  void _refreshUnreadCount() {
    if (!mounted) return;

    setState(() {
      _unreadMessages = MessageHiveService.getUnreadCount();
    });
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final Color cardColor = kMatiereGreen;

    final items = <_MenuItem>[
      _MenuItem(
        titre: 'À propos',
        icone: Icons.info_outline_rounded,
        couleur: cardColor,
        onTap: () {
          _push(
            const AboutAmbitionPage(),
          );
        },
      ),
      _MenuItem(
        titre: 'Messages',
        icone: Icons.mark_email_unread_rounded,
        couleur: cardColor,
        badge: _unreadMessages,
        onTap: () {
          _push(
            const MessagesPage(),
          );
        },
      ),
      _MenuItem(
        titre: 'Mes classements',
        icone: Icons.emoji_events_rounded,
        couleur: cardColor,
        onTap: () {
          _push(
            const ClassementPage(),
          );
        },
      ),
      _MenuItem(
        titre: 'Mes statistiques',
        icone: Icons.bar_chart_rounded,
        couleur: cardColor,
        onTap: () {
          _push(
            const StatistiquesPage(),
          );
        },
      ),
      _MenuItem(
        titre: 'Administration',
        icone: Icons.admin_panel_settings_rounded,
        couleur: cardColor,
        onTap: () {
          _push(
            const AdministrationPage(),
          );
        },
      ),
      _MenuItem(
        titre: 'Espace Premium',
        icone: Icons.workspace_premium_rounded,
        couleur: cardColor,
        onTap: () {
          _push(
            const VipPage(),
          );
        },
      ),
      _MenuItem(
        titre: 'Paramètres',
        icone: Icons.settings_rounded,
        couleur: cardColor,
        onTap: () {
          _showParametresSheet(context);
        },
      ),
      _MenuItem(
        titre: 'Déconnexion',
        icone: Icons.logout_rounded,
        couleur: cardColor,
        onTap: widget.onLogout,
      ),
    ];

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 1.3,
      ),
      itemBuilder: (context, index) {
        final item = items[index];

        return _PlusCard(
          item: item,
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // PARAMÈTRES
  // ---------------------------------------------------------------------------

  void _showParametresSheet(
    BuildContext context,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (_) => const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Paramètres — à implémenter.',
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 🟩 CARTE PLUS
// -----------------------------------------------------------------------------

class _PlusCard extends StatelessWidget {
  final _MenuItem item;

  const _PlusCard({
    required this.item,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: item.couleur,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: item.onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // -----------------------------------------------------------------
            // CONTENU
            // -----------------------------------------------------------------

            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 12,
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      item.icone,
                      color: Colors.white,
                      size: 32,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      item.titre,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // -----------------------------------------------------------------
            // 🔴 BADGE NON LUS
            // -----------------------------------------------------------------

            if (item.badge > 0)
              Positioned(
                top: -7,
                right: -7,
                child: Container(
                  constraints: const BoxConstraints(
                    minWidth: 27,
                    minHeight: 27,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                  ),
                  decoration: BoxDecoration(
                    color: _messagesRed,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white,
                      width: 2.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.20),
                        blurRadius: 5,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      item.badge > 99 ? '99+' : item.badge.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// 📁 lib/tabs/messages_page.dart

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

// -----------------------------------------------------------------------------
// 🎨 CONSTANTES
// -----------------------------------------------------------------------------

const Color _primaryColor = Color(0xFFFF8C00);
const Color _backgroundColor = Color(0xFFFFF4F0);

const String _logoAmbitionBac = 'assets/images/outils/logo_ambitionbac.png';

const String _logoWatermark = 'assets/images/outils/logo_ambition.png';

// -----------------------------------------------------------------------------
// 📦 HIVE
// -----------------------------------------------------------------------------

const String messagesHiveBox = 'messages_box';

const String messagesHiveKey = 'messages';

const String readMessagesHiveKey = 'read_message_ids';

// -----------------------------------------------------------------------------
// 📜 MODÈLE MESSAGE
// -----------------------------------------------------------------------------

class Message {
  final String id;
  final String title;
  final String content;
  final DateTime date;
  final String status;
  final String icon;

  Message({
    required this.id,
    required this.title,
    required this.content,
    required this.date,
    required this.status,
    required this.icon,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'].toString(),
      title: json['title']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      date: DateTime.tryParse(
            json['date']?.toString() ?? '',
          ) ??
          DateTime.now(),
      status: (json['status']?.toString() ?? 'FREE').toUpperCase(),
      icon: json['icon']?.toString() ?? 'message',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'date': date.toIso8601String(),
      'status': status,
      'icon': icon,
    };
  }

  IconData get flutterIcon {
    switch (icon.toLowerCase()) {
      case 'welcome':
        return Icons.waving_hand_rounded;

      case 'coach':
        return Icons.psychology_rounded;

      case 'target':
        return Icons.ads_click_rounded;

      case 'success':
        return Icons.star_rounded;

      case 'reward':
        return Icons.emoji_events_rounded;

      case 'premium':
        return Icons.workspace_premium_rounded;

      case 'security':
        return Icons.security_rounded;

      case 'upgrade':
        return Icons.rocket_launch_rounded;

      case 'diamond':
        return Icons.diamond_rounded;

      case 'trophy':
        return Icons.military_tech_rounded;

      case 'update':
        return Icons.auto_awesome_rounded;

      case 'chat':
        return Icons.chat_bubble_rounded;

      case 'fire':
        return Icons.local_fire_department_rounded;

      case 'battle':
        return Icons.shield_rounded;

      case 'future':
        return Icons.auto_graph_rounded;

      default:
        return Icons.mark_email_unread_rounded;
    }
  }

  bool get isPremium => status == 'PREMIUM';

  bool get isAll => status == 'ALL';

  bool get isFree => status == 'FREE';
}

// -----------------------------------------------------------------------------
// 💾 SERVICE HIVE
// -----------------------------------------------------------------------------

class MessageHiveService {
  static Box get _box => Hive.box(messagesHiveBox);

  // ---------------------------------------------------------------------------
  // ENREGISTRER LES MESSAGES
  // ---------------------------------------------------------------------------

  static Future<void> saveMessages(List<Message> messages) async {
    final data = messages.map((m) => m.toJson()).toList();

    await _box.put(
      messagesHiveKey,
      jsonEncode(data),
    );
  }

  // ---------------------------------------------------------------------------
  // LIRE LES MESSAGES
  // ---------------------------------------------------------------------------

  static List<Message> getMessages() {
    final raw = _box.get(messagesHiveKey);

    if (raw == null) {
      return [];
    }

    try {
      final List<dynamic> data = jsonDecode(raw.toString());

      final messages = data
          .map(
            (item) => Message.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList();

      messages.sort(
        (a, b) => b.date.compareTo(a.date),
      );

      return messages;
    } catch (e) {
      debugPrint(
        'Erreur lecture messages Hive : $e',
      );

      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // IDS LUS
  // ---------------------------------------------------------------------------

  static Set<String> getReadMessageIds() {
    final raw = _box.get(readMessagesHiveKey);

    if (raw == null) {
      return {};
    }

    if (raw is List) {
      return raw.map((e) => e.toString()).toSet();
    }

    try {
      final List<dynamic> data = jsonDecode(raw.toString());

      return data.map((e) => e.toString()).toSet();
    } catch (_) {
      return {};
    }
  }

  // ---------------------------------------------------------------------------
  // MARQUER COMME LU
  // ---------------------------------------------------------------------------

  static Future<void> markAsRead(String messageId) async {
    final ids = getReadMessageIds();

    ids.add(messageId);

    await _box.put(
      readMessagesHiveKey,
      ids.toList(),
    );
  }

  // ---------------------------------------------------------------------------
  // NOMBRE NON LUS
  // ---------------------------------------------------------------------------

  static int getUnreadCount() {
    final messages = getMessages();
    final readIds = getReadMessageIds();

    return messages.where((message) => !readIds.contains(message.id)).length;
  }
}

// -----------------------------------------------------------------------------
// 📲 PAGE MESSAGES
// -----------------------------------------------------------------------------

class MessagesPage extends StatefulWidget {
  const MessagesPage({
    super.key,
  });

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  List<Message> _messages = [];
  Set<String> _readMessageIds = {};

  @override
  void initState() {
    super.initState();

    Intl.defaultLocale = 'fr';

    _loadFromHive();
  }

  // ---------------------------------------------------------------------------
  // CHARGEMENT UNIQUEMENT HIVE
  // ---------------------------------------------------------------------------

  void _loadFromHive() {
    final messages = MessageHiveService.getMessages();
    final readIds = MessageHiveService.getReadMessageIds();

    if (!mounted) return;

    setState(() {
      _messages = messages;
      _readMessageIds = readIds;
    });
  }

  // ---------------------------------------------------------------------------
  // OUVERTURE MESSAGE
  // ---------------------------------------------------------------------------

  Future<void> _openMessage(Message message) async {
    if (!_readMessageIds.contains(message.id)) {
      await MessageHiveService.markAsRead(message.id);

      if (mounted) {
        setState(() {
          _readMessageIds.add(message.id);
        });
      }
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return _MessageDetailsSheet(
          message: message,
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        backgroundColor: _primaryColor,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'MESSAGES',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: Colors.white,
          ),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(
              right: 12,
            ),
            child: ClipOval(
              child: Image.asset(
                _logoAmbitionBac,
                width: 38,
                height: 38,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) {
                  return const Icon(
                    Icons.school_rounded,
                    color: Colors.white,
                  );
                },
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // -------------------------------------------------------------------
          // FILIGRANE
          // -------------------------------------------------------------------

          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Opacity(
                  opacity: 0.055,
                  child: Image.asset(
                    _logoWatermark,
                    width: MediaQuery.of(context).size.width * 0.75,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) {
                      return const SizedBox.shrink();
                    },
                  ),
                ),
              ),
            ),
          ),

          // -------------------------------------------------------------------
          // CONTENU
          // -------------------------------------------------------------------

          if (_messages.isEmpty)
            _buildEmptyState()
          else
            RefreshIndicator(
              color: _primaryColor,
              onRefresh: () async {
                _loadFromHive();
              },
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  14,
                  16,
                  14,
                  30,
                ),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final message = _messages[index];

                  final isRead = _readMessageIds.contains(
                    message.id,
                  );

                  return _MessageCard(
                    message: message,
                    isRead: isRead,
                    onTap: () {
                      _openMessage(message);
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ÉTAT VIDE
  // ---------------------------------------------------------------------------

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 85,
              height: 85,
              decoration: BoxDecoration(
                color: _primaryColor.withOpacity(0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.mark_email_read_rounded,
                size: 42,
                color: _primaryColor,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Aucun message',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tu recevras ici les actualités et '
              'informations importantes d’Ambition+.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade600,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 📨 CARTE MESSAGE
// -----------------------------------------------------------------------------

class _MessageCard extends StatelessWidget {
  final Message message;
  final bool isRead;
  final VoidCallback onTap;

  const _MessageCard({
    required this.message,
    required this.isRead,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(
        bottom: 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(
              isRead ? 0.05 : 0.09,
            ),
            blurRadius: isRead ? 8 : 14,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: isRead ? Colors.transparent : _primaryColor.withOpacity(0.25),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // -------------------------------------------------------------
                // ICÔNE
                // -------------------------------------------------------------

                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: message.isPremium
                        ? Colors.amber.withOpacity(
                            0.14,
                          )
                        : _primaryColor.withOpacity(
                            0.10,
                          ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    message.flutterIcon,
                    color: message.isPremium
                        ? Colors.amber.shade700
                        : _primaryColor,
                    size: 27,
                  ),
                ),

                const SizedBox(width: 13),

                // -------------------------------------------------------------
                // TEXTE
                // -------------------------------------------------------------

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              message.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15.5,
                                height: 1.2,
                                fontWeight:
                                    isRead ? FontWeight.w600 : FontWeight.w800,
                              ),
                            ),
                          ),
                          if (!isRead)
                            Container(
                              width: 9,
                              height: 9,
                              margin: const EdgeInsets.only(
                                left: 7,
                                top: 3,
                              ),
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      Text(
                        message.content,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Row(
                        children: [
                          Icon(
                            Icons.schedule_rounded,
                            size: 13,
                            color: Colors.grey.shade500,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            DateFormat(
                              'dd MMM yyyy • HH:mm',
                            ).format(
                              message.date.toLocal(),
                            ),
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade500,
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 20,
                            color: Colors.grey.shade400,
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
}

// -----------------------------------------------------------------------------
// 📖 DÉTAIL MESSAGE
// -----------------------------------------------------------------------------

class _MessageDetailsSheet extends StatelessWidget {
  final Message message;

  const _MessageDetailsSheet({
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: const BoxDecoration(
        color: _backgroundColor,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(28),
        ),
      ),
      child: Column(
        children: [
          // -------------------------------------------------------------------
          // HANDLE
          // -------------------------------------------------------------------

          const SizedBox(height: 10),

          Container(
            width: 42,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(10),
            ),
          ),

          // -------------------------------------------------------------------
          // HEADER
          // -------------------------------------------------------------------

          Padding(
            padding: const EdgeInsets.fromLTRB(
              20,
              20,
              12,
              12,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: message.isPremium
                        ? Colors.amber.withOpacity(
                            0.15,
                          )
                        : _primaryColor.withOpacity(
                            0.10,
                          ),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(
                    message.flutterIcon,
                    color: message.isPremium
                        ? Colors.amber.shade700
                        : _primaryColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message.title,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        DateFormat(
                          'EEEE dd MMMM yyyy à HH:mm',
                        ).format(
                          message.date.toLocal(),
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  icon: const Icon(
                    Icons.close_rounded,
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // -------------------------------------------------------------------
          // CONTENU
          // -------------------------------------------------------------------

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                20,
                20,
                20,
                30,
              ),
              child: Text(
                message.content,
                style: const TextStyle(
                  fontSize: 15.5,
                  height: 1.65,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

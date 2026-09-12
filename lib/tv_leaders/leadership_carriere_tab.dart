// 📁 lib/tv_leaders/leadership_carriere_tab.dart

import 'package:flutter/material.dart';
import '../accueil/app_shared.dart';
import 'entrepreneuriat_page.dart';
import 'tvambition_tab.dart';

class LeadershipCarriereTab extends StatefulWidget {
  final TabUpdateCallback onUpdate;

  const LeadershipCarriereTab({super.key, required this.onUpdate});

  @override
  State<LeadershipCarriereTab> createState() => _LeadershipCarriereTabState();
}

class _LeadershipCarriereTabState extends State<LeadershipCarriereTab>
    with TickerProviderStateMixin {
  late final TabController _tabController =
      TabController(length: 2, vsync: this)..addListener(_onChange);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onUpdate(title: 'AMBITION+ TV', onBack: null);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _onChange() {
    if (_tabController.indexIsChanging) return;
    final titles = ['LEADERSHIP', 'AMBITION+ TV'];
    widget.onUpdate(
      title: titles[_tabController.index],
      onBack: null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: kAppOrange, // Fond orange comme l'AppBar
          child: TabBar(
            controller: _tabController,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: const [
              Tab(icon: Icon(Icons.rocket_launch), text: 'Leadership'),
              Tab(icon: Icon(Icons.tv), text: 'Ambition+ TV'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              EntrepreneuriatPage(onUpdate: widget.onUpdate),
              const TvAmbitionTab(),
            ],
          ),
        ),
      ],
    );
  }
}
 
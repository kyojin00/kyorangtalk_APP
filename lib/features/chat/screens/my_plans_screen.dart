import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../services/plan_service.dart';
import '../widgets/plan_card_widget.dart';

/// ═══════════════════════════════════════════════════
/// 내 약속 모아보기 페이지
/// ═══════════════════════════════════════════════════
class MyPlansScreen extends ConsumerStatefulWidget {
  const MyPlansScreen({super.key});

  @override
  ConsumerState<MyPlansScreen> createState() => _MyPlansScreenState();
}

class _MyPlansScreenState extends ConsumerState<MyPlansScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool _loadingUpcoming = true;
  bool _loadingPast = true;
  List<PlanModel> _upcoming = [];
  List<PlanModel> _past = [];
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _disposed = true;
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    await Future.wait([
      _loadUpcoming(),
      _loadPast(),
    ]);
  }

  Future<void> _loadUpcoming() async {
    if (!_disposed && mounted) setState(() => _loadingUpcoming = true);
    final list = await PlanService.fetchMyUpcoming();
    if (!_disposed && mounted) {
      setState(() {
        _upcoming = list;
        _loadingUpcoming = false;
      });
    }
  }

  Future<void> _loadPast() async {
    if (!_disposed && mounted) setState(() => _loadingPast = true);
    final list = await PlanService.fetchMyPast(limit: 100);
    if (!_disposed && mounted) {
      setState(() {
        _past = list;
        _loadingPast = false;
      });
    }
  }

  /// 약속 업데이트 시 (완료/취소 등)
  /// - upcoming → completed/cancelled로 바뀌면 다가오는 탭에서 제거 + 지난 탭에 추가
  void _handlePlanUpdated(PlanModel updated) {
    if (_disposed || !mounted) return;
    setState(() {
      // upcoming 리스트에서 제거 (status 바뀐 경우)
      _upcoming.removeWhere((p) => p.id == updated.id);
      // past 리스트에서도 제거 (덮어쓰기 위해)
      _past.removeWhere((p) => p.id == updated.id);

      // 새 status에 맞춰 적절한 리스트에 추가
      if (updated.status == 'upcoming' &&
          updated.scheduledAt.isAfter(DateTime.now())) {
        _upcoming.add(updated);
        _upcoming.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
      } else {
        _past.insert(0, updated);
      }
    });
  }

  void _handlePlanDismissed(String planId) {
    if (_disposed || !mounted) return;
    setState(() {
      _upcoming.removeWhere((p) => p.id == planId);
      _past.removeWhere((p) => p.id == planId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios,
              color: AppTheme.primaryLight, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '내 약속',
          style: TextStyle(
            color: AppTheme.textMain,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: AppTheme.textSub, size: 20),
            onPressed: _loadAll,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppTheme.border, width: 1),
              ),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorColor: AppTheme.primary,
              indicatorWeight: 2.5,
              labelColor: AppTheme.primary,
              unselectedLabelColor: AppTheme.textSub,
              labelStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              tabs: [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('다가오는 약속'),
                      if (_upcoming.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${_upcoming.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Tab(text: '지난 약속'),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildUpcomingTab(),
          _buildPastTab(),
        ],
      ),
    );
  }

  Widget _buildUpcomingTab() {
    if (_loadingUpcoming) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }

    if (_upcoming.isEmpty) {
      return _buildEmpty(
        icon: Icons.event_available_outlined,
        title: '다가오는 약속이 없어요',
        subtitle: '채팅에서 약속을 정하면\nAI가 자동으로 정리해드려요',
      );
    }

    final grouped = _groupUpcoming(_upcoming);

    return RefreshIndicator(
      color: AppTheme.primary,
      backgroundColor: AppTheme.bgCard,
      onRefresh: _loadUpcoming,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: [
          for (final entry in grouped.entries) ...[
            _buildSectionHeader(entry.key),
            const SizedBox(height: 8),
            for (final plan in entry.value) ...[
              PlanCard(
                plan: plan,
                onUpdated: _handlePlanUpdated,
                onDismissed: () => _handlePlanDismissed(plan.id),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  Widget _buildPastTab() {
    if (_loadingPast) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }

    if (_past.isEmpty) {
      return _buildEmpty(
        icon: Icons.history_outlined,
        title: '지난 약속이 없어요',
        subtitle: '약속이 끝나면 여기에 모여요',
      );
    }

    final grouped = _groupPast(_past);

    return RefreshIndicator(
      color: AppTheme.primary,
      backgroundColor: AppTheme.bgCard,
      onRefresh: _loadPast,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: [
          for (final entry in grouped.entries) ...[
            _buildSectionHeader(entry.key),
            const SizedBox(height: 8),
            for (final plan in entry.value) ...[
              PlanCard(
                plan: plan,
                onUpdated: _handlePlanUpdated,
                onDismissed: () => _handlePlanDismissed(plan.id),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Text(
        title,
        style: TextStyle(
          color: AppTheme.textSub,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildEmpty({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppTheme.primary, size: 32),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              color: AppTheme.textMain,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.textSub,
              fontSize: 12.5,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // 그룹핑 헬퍼
  // ═══════════════════════════════════════════════════
  Map<String, List<PlanModel>> _groupUpcoming(List<PlanModel> plans) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final weekEnd = today.add(const Duration(days: 7));

    final groups = <String, List<PlanModel>>{};

    for (final plan in plans) {
      final local = plan.scheduledAt.toLocal();
      final target = DateTime(local.year, local.month, local.day);

      String key;
      if (target == today) {
        key = '오늘';
      } else if (target == tomorrow) {
        key = '내일';
      } else if (target.isBefore(weekEnd)) {
        key = '이번 주';
      } else {
        key = '나중에';
      }

      groups.putIfAbsent(key, () => []).add(plan);
    }

    final ordered = <String, List<PlanModel>>{};
    for (final key in ['오늘', '내일', '이번 주', '나중에']) {
      if (groups.containsKey(key)) ordered[key] = groups[key]!;
    }
    return ordered;
  }

  Map<String, List<PlanModel>> _groupPast(List<PlanModel> plans) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekStart = today.subtract(const Duration(days: 7));
    final monthStart = today.subtract(const Duration(days: 30));

    final groups = <String, List<PlanModel>>{};

    for (final plan in plans) {
      final local = plan.scheduledAt.toLocal();
      final target = DateTime(local.year, local.month, local.day);

      String key;
      if (target.isAfter(weekStart)) {
        key = '최근 7일';
      } else if (target.isAfter(monthStart)) {
        key = '이번 달';
      } else {
        key = '더 이전';
      }

      groups.putIfAbsent(key, () => []).add(plan);
    }

    final ordered = <String, List<PlanModel>>{};
    for (final key in ['최근 7일', '이번 달', '더 이전']) {
      if (groups.containsKey(key)) ordered[key] = groups[key]!;
    }
    return ordered;
  }
}
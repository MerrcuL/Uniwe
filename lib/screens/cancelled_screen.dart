import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/cancelled_lecture.dart';
import '../models/timetable_event.dart';
import '../services/auth_service.dart';
import '../services/cache_service.dart';
import '../services/cancellation_store.dart';
import '../services/haptic_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import '../utils/formats.dart';
import '../utils/iso_week.dart';
import '../widgets/expressive.dart';
import '../widgets/info_widgets.dart';
import 'lsf_browser_screen.dart';

/// The user's classes on [date] from the cached timetable (empty when that
/// week has not been loaded).
List<TimetableEvent> cachedEventsOn(DateTime date) {
  final key = CacheService.weekKey(IsoWeek.fromDate(date).key);
  final data = CacheService.instance.read(key).data;
  if (data is! List) return const [];
  try {
    return [
      for (final e in data)
        TimetableEvent.fromJson(Map<String, dynamic>.from(e as Map)),
    ].where((e) => e.dayIndex == date.weekday - 1).toList();
  } catch (_) {
    return const [];
  }
}

/// LSF's "Ausfallende Veranstaltungen": every class of the university that
/// is cancelled on a day, the user's own ones first.
class CancelledScreen extends StatefulWidget {
  const CancelledScreen({super.key});

  @override
  State<CancelledScreen> createState() => _CancelledScreenState();
}

class _CancelledScreenState extends State<CancelledScreen> {
  static const int _dayCount = 7;

  late final CancellationStore _store = context.read<CancellationStore>();
  late DateTime _selected = Dates.today();

  /// 'all' or a campus prefix ('WH', 'TA', 'TGS').
  String _campus = 'all';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _store.refresh(_selected);
    });
  }

  void _select(DateTime date) {
    if (Dates.isSameDay(date, _selected)) return;
    HapticService.selection(context.read<SettingsService>().hapticsEnabled);
    setState(() => _selected = date);
    _store.refresh(date);
  }

  Future<void> _refresh() => _store.refresh(_selected, force: true);

  void _open(CancelledLecture lecture) {
    final publishId = lecture.publishId;
    if (publishId == null) return;
    if (!context.read<AuthService>().isAuthenticated) return;
    HapticService.confirm(context.read<SettingsService>().hapticsEnabled);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LsfBrowserScreen(publishId: publishId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final animate =
        context.select<SettingsService, bool>((s) => s.animationsEnabled);
    final today = Dates.today();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.get('cancelledClasses'))),
      body: Column(
        children: [
          SizedBox(
            height: DayPill.height + 16,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Row(
                children: [
                  for (var d = 0; d < _dayCount; d++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Builder(builder: (context) {
                          final date = DateTime(
                            today.year,
                            today.month,
                            today.day + d,
                          );
                          return DayPill(
                            weekday: Formats.weekdayShort(date, locale),
                            day: date.day.toString(),
                            selected: Dates.isSameDay(date, _selected),
                            isToday: d == 0,
                            semanticLabel: Formats.fullDate(date, locale),
                            animate: animate,
                            onTap: () => _select(date),
                          );
                        }),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.gutter(context),
            ),
            child: ConnectedButtonGroup<String>(
              items: [
                ButtonGroupItem(value: 'all', label: l10n.get('allCampuses')),
                const ButtonGroupItem(value: 'WH', label: 'WH'),
                const ButtonGroupItem(value: 'TA', label: 'TA'),
                const ButtonGroupItem(value: 'TGS', label: 'TGS'),
              ],
              selected: _campus,
              onChanged: (campus) {
                HapticService.selection(
                  context.read<SettingsService>().hapticsEnabled,
                );
                setState(() => _campus = campus);
              },
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListenableBuilder(
              listenable: _store,
              builder: (context, _) => _buildList(context, l10n),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context, AppLocalizations l10n) {
    final lectures = _store.forDate(_selected);
    final failed = _store.hasFailed(_selected) && !_store.isLoading(_selected);

    if (lectures == null) {
      if (!failed) return const LoadingState();
      return StatusMessage(
        icon: Icons.cloud_off_outlined,
        shape: SoftShape.clover,
        title: l10n.get('errorCancelled'),
        action: FilledButton.tonalIcon(
          onPressed: _refresh,
          icon: const Icon(Icons.refresh_rounded),
          label: Text(l10n.get('retry')),
        ),
      );
    }

    final myEvents = cachedEventsOn(_selected);
    bool isMine(CancelledLecture l) => myEvents.any(l.matches);
    final mine = lectures.where(isMine).toList();
    final others = lectures
        .where((l) => !isMine(l))
        .where((l) => _campus == 'all' || l.campus == _campus)
        .toList();
    final gutter = AppSpacing.gutter(context);
    final fetchedAt = _store.fetchedAt(_selected);

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          gutter,
          0,
          gutter,
          AppSpacing.bottomInset(context),
        ),
        children: [
          if (failed)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: InfoBanner(
                icon: Icons.cloud_off_outlined,
                text: fetchedAt == null
                    ? l10n.get('offlineCache')
                    : '${l10n.get('offlineCache')} '
                        '${l10n.get('lastUpdated')}: ${Formats.timestamp(fetchedAt)}',
              ),
            ),
          if (mine.isNotEmpty) ...[
            SectionHeader(
              l10n.get('cancelledMine'),
              icon: Icons.person_outline_rounded,
            ),
            ListGroup(
              children: [
                for (final lecture in mine)
                  _CancelledTile(
                    lecture: lecture,
                    mine: true,
                    onTap: () => _open(lecture),
                  ),
              ],
            ),
          ],
          if (mine.isEmpty && others.isEmpty)
            SizedBox(
              height: 360,
              child: StatusMessage(
                icon: Icons.event_available_outlined,
                shape: SoftShape.flower,
                title: l10n.get('cancelledNone'),
                message: l10n.get('cancelledNoneMessage'),
              ),
            ),
          if (others.isNotEmpty) ...[
            SectionHeader(
              '${l10n.get('cancelledAll')} · ${others.length}',
              icon: Icons.event_busy_outlined,
            ),
            ListGroup(
              children: [
                for (final lecture in others)
                  _CancelledTile(
                    lecture: lecture,
                    onTap: () => _open(lecture),
                  ),
              ],
            ),
          ],
          if (lectures.isNotEmpty) FootNote(l10n.get('cancelledHint')),
        ],
      ),
    );
  }
}

class _CancelledTile extends StatelessWidget {
  const _CancelledTile({
    required this.lecture,
    required this.onTap,
    this.mine = false,
  });

  final CancelledLecture lecture;
  final VoidCallback onTap;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return InkWell(
      onTap: lecture.publishId == null ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TimeBlock(
              start: lecture.start,
              end: lecture.end,
              background:
                  mine ? scheme.errorContainer : scheme.surfaceContainerHighest,
              foreground:
                  mine ? scheme.onErrorContainer : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lecture.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  if (lecture.room.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: IconLine(
                        icon: Icons.location_on_outlined,
                        label: lecture.room,
                      ),
                    ),
                  if (lecture.group.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: IconLine(
                        icon: Icons.groups_outlined,
                        label: lecture.group,
                      ),
                    ),
                  if (lecture.remark.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: IconLine(
                        icon: Icons.info_outline_rounded,
                        label: lecture.remark,
                        color: scheme.onSurface,
                        maxLines: 3,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

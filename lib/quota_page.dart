import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'cron_page.dart';
import 'hermes.dart';
import 'l10n/app_localizations.dart';
import 'settings.dart';

/// "4h 12min"-style text for [d] (its absolute value), at least one minute.
String durationText(AppLocalizations l, Duration d) {
  d = d.abs();
  if (d.inDays > 0) return l.durationDays(d.inDays, d.inHours % 24);
  if (d.inHours > 0) return l.durationHours(d.inHours, d.inMinutes % 60);
  return l.durationMinutes(d.inMinutes < 1 ? 1 : d.inMinutes);
}

/// Usage of every subscription provider the Hermes server reports.
class QuotaPage extends StatefulWidget {
  const QuotaPage({super.key});

  @override
  State<QuotaPage> createState() => _QuotaPageState();
}

class _QuotaPageState extends State<QuotaPage> {
  List<Quota>? quotas;
  Object? error;
  bool failed = false;
  Usage? usage;
  var days = 7;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    loadUsage();
    await loadQuotas();
  }

  /// The server answers from its cache and fills it in the background: a cold one (just restarted) has
  /// nothing yet, so a quota missing is asked for again once, [again] seconds later.
  Future<void> loadQuotas({int again = 3}) async {
    try {
      final r = await serverOptions();
      if (!mounted) return;
      setState(() {
        quotas = r?.quotas;
        failed = r == null;
        error = null;
      });
      if (again > 0 && (r?.quotas.any((q) => q.windows.isEmpty && !q.limited) ?? false)) {
        await Future<void>.delayed(Duration(seconds: again));
        if (mounted) await loadQuotas(again: 0);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        failed = true;
        error = e;
      });
    }
  }

  Future<void> loadUsage() async {
    try {
      final body = await serverApi('GET', '/api/analytics/usage', query: {'days': '$days'});
      if (mounted) setState(() => usage = body == null ? null : parseUsage(body));
    } catch (e) {
      debugPrint('Usage: $e'); // the quotas above still show
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    final known = quotas?.where((q) => q.windows.isNotEmpty || q.limited).toList() ?? [];
    final unknown = quotas?.where((q) => q.windows.isEmpty && !q.limited).toList() ?? [];

    Widget section(String title, List<Widget> children, {String? footer}) => CupertinoListSection.insetGrouped(
      backgroundColor: c.surface,
      decoration: BoxDecoration(color: c.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
      separatorColor: c.outline.withValues(alpha: .2),
      header: Text(title.toUpperCase(), style: TextStyle(fontSize: 13, color: c.outline)),
      footer: footer == null ? null : Text(footer, style: TextStyle(fontSize: 13, color: c.outline)),
      children: children,
    );

    return PageFrame(
      title: l.quotas,
      child: quotas == null && !failed
          ? const Center(child: CupertinoActivityIndicator())
          : RefreshIndicator.adaptive(
              onRefresh: load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  if (failed)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(32, 48, 32, 0),
                      child: Text(
                        serverErrorText(l, error),
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 15, color: c.outline),
                      ),
                    ),
                  // one card per provider, its accounts and windows inside
                  for (final provider in {for (final q in known) q.provider})
                    section(provider, [for (final q in known.where((q) => q.provider == provider)) _QuotaTile(q)]),
                  if (unknown.isNotEmpty)
                    section(l.quotaNoData, [
                      for (final q in unknown)
                        CupertinoListTile(
                          title: Text(
                            q.account.isEmpty ? q.provider : '${q.provider} · ${q.account}',
                            style: TextStyle(fontSize: 16, color: c.onSurface),
                          ),
                        ),
                    ]),
                  if (quotas != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(36, 4, 36, 0),
                      child: Text(l.quotaFooter, style: TextStyle(fontSize: 13, color: c.outline)),
                    ),
                  if (usage case final u?) ...[
                    section(
                      l.usage,
                      [
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: CupertinoSlidingSegmentedControl<int>(
                            groupValue: days,
                            onValueChanged: (v) {
                              setState(() => days = v ?? days);
                              loadUsage();
                            },
                            children: {
                              for (final n in [7, 30, 90]) n: Text(l.usageDays(n)),
                            },
                          ),
                        ),
                        _UsageChart(u),
                      ],
                      footer: u.cache > 0
                          ? l.usageCache(NumberFormat.compact(locale: '${Localizations.localeOf(context)}').format(u.cache))
                          : null,
                    ),
                    if (u.models.isNotEmpty)
                      section(l.usageByModel, [
                        for (final m in u.models)
                          CupertinoListTile(
                            title: Text(m.name, style: TextStyle(fontSize: 16, color: c.onSurface)),
                            additionalInfo: Text(_usageLine(context, m), style: TextStyle(fontSize: 13, color: c.outline)),
                          ),
                      ]),
                  ],
                ],
              ),
            ),
    );
  }
}

class _QuotaTile extends StatelessWidget {
  const _QuotaTile(this.q);
  final Quota q;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    String until(DateTime t) => durationText(l, t.difference(DateTime.now()));

    final small = TextStyle(fontSize: 13, color: c.outline);
    final pct = NumberFormat.percentPattern(Localizations.localeOf(context).toString());
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (q.account.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                q.account,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.onSurface),
              ),
            ),
          if (q.limited)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                q.limitedUntil == null ? l.quotaLimited : l.quotaLimitedUntil(until(q.limitedUntil!)),
                style: const TextStyle(fontSize: 13, color: CupertinoColors.systemRed),
              ),
            ),
          for (final (i, w) in q.windows.indexed) ...[
            if (i > 0) const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(w.label, style: TextStyle(fontSize: 16, color: c.onSurface)),
                ),
                Text(
                  pct.format(w.used / 100),
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: c.onSurface),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: (w.used / 100).clamp(0, 1),
                minHeight: 6,
                backgroundColor: c.outline.withValues(alpha: .2),
                color: w.used >= 90
                    ? CupertinoColors.systemRed
                    : w.used >= 70
                    ? CupertinoColors.systemOrange
                    : c.onSurface,
              ),
            ),
            if (w.resetsAt != null) ...[const SizedBox(height: 4), Text(l.quotaResets(until(w.resetsAt!)), style: small)],
          ],
        ],
      ),
    );
  }
}

/// "1.2M · $0.84" for a usage row.
String _usageLine(BuildContext context, UsageRow r) {
  final locale = '${Localizations.localeOf(context)}';
  return [
    NumberFormat.compact(locale: locale).format(r.input + r.output),
    if (r.cost > 0) NumberFormat.simpleCurrency(locale: locale, name: 'USD').format(r.cost),
  ].join(' · ');
}

/// The period's totals over a bar per day of tokens used.
class _UsageChart extends StatelessWidget {
  const _UsageChart(this.u);
  final Usage u;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    final locale = '${Localizations.localeOf(context)}';
    final small = TextStyle(fontSize: 13, color: c.outline);
    final peak = u.days.fold(1, (m, d) => d.input + d.output > m ? d.input + d.output : m);
    String day(String d) => DateTime.tryParse(d) == null ? d : DateFormat.MMMd(locale).format(DateTime.parse(d));
    Widget total(String value, String label) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: c.onSurface),
          ),
          Text(label, style: small),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              total(NumberFormat.compact(locale: locale).format(u.total.input + u.total.output), l.usageTokens),
              total(NumberFormat.simpleCurrency(locale: locale, name: 'USD').format(u.total.cost), l.usageCost),
              total('${u.total.sessions}', l.usageSessions),
            ],
          ),
          if (u.days.isNotEmpty) ...[
            const SizedBox(height: 16),
            SizedBox(
              height: 64,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final d in u.days)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1),
                        child: FractionallySizedBox(
                          heightFactor: ((d.input + d.output) / peak).clamp(.03, 1),
                          child: DecoratedBox(
                            decoration: BoxDecoration(color: c.onSurface, borderRadius: BorderRadius.circular(2)),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(day(u.days.first.name), style: small),
                Text(day(u.days.last.name), style: small),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

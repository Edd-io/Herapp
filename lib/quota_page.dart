import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await serverOptions();
      if (!mounted) return;
      setState(() {
        quotas = r?.quotas;
        failed = r == null;
        error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        failed = true;
        error = e;
      });
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

    return Scaffold(
      backgroundColor: c.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            SizedBox(
              height: 52,
              width: double.infinity,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Text(
                    l.quotas,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.onSurface),
                  ),
                  Positioned(
                    left: 4,
                    child: IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(CupertinoIcons.chevron_back, color: c.onSurface),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
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
                        ],
                      ),
                    ),
            ),
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

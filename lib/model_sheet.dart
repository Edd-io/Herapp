import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'hermes.dart';
import 'l10n/app_localizations.dart';
import 'settings.dart';

/// Server models; [error] is the failure to show (see [serverErrorText]), null when the list loaded.
typedef Models = ({List<Model> list, bool loading, String? error});

/// The reasoning levels Hermes takes; '' leaves it to the server's setting.
const efforts = ['', 'minimal', 'low', 'medium', 'high', 'xhigh', 'max'];

String effortText(AppLocalizations l, String effort) => switch (effort) {
  'minimal' => l.effortMinimal,
  'low' => l.effortLow,
  'medium' => l.effortMedium,
  'high' => l.effortHigh,
  'xhigh' => l.effortXhigh,
  'max' => l.effortMax,
  '' => l.effortAuto,
  _ => effort,
};

/// Fills [into] with the server's models (for pages that don't keep the chat's list).
Future<void> loadServerModels(ValueNotifier<Models> into, AppLocalizations l) async {
  into.value = (list: into.value.list, loading: true, error: null);
  try {
    final r = await serverOptions();
    into.value = r == null
        ? (list: const [], loading: false, error: serverErrorText(l, null))
        : (list: r.models, loading: false, error: null);
  } catch (e) {
    debugPrint('Models: $e');
    into.value = (list: into.value.list, loading: false, error: serverErrorText(l, e));
  }
}

/// Model picker sheet, grouped by provider, with the reasoning effort on top: an effort pick goes to
/// [onEffort] at once, a model pick closes the sheet with its id ('' for [allowDefault]'s server default).
Future<String?> showModelSheet(
  BuildContext context, {
  required ValueListenable<Models> models,
  required String current,
  required String effort,
  required ValueChanged<String> onEffort,
  bool allowDefault = false,
}) async {
  final id = await showPanel<String>(
    context,
    (context) => ModelSheet(models: models, current: current, effort: effort, onEffort: onEffort, allowDefault: allowDefault),
    scrollControlled: true,
  );
  if (id != null && id.isNotEmpty) settings.usedModel(id);
  return id;
}

class ModelSheet extends StatefulWidget {
  const ModelSheet({
    super.key,
    required this.models,
    required this.current,
    required this.effort,
    required this.onEffort,
    this.allowDefault = false,
  });
  final ValueListenable<Models> models;
  final String current, effort;
  final ValueChanged<String> onEffort;
  final bool allowDefault;

  @override
  State<ModelSheet> createState() => _ModelSheetState();
}

class _ModelSheetState extends State<ModelSheet> {
  late String effort = widget.effort;
  var all = false; // every model, not only the recent ones

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .8),
      child: ValueListenableBuilder<Models>(
        valueListenable: widget.models,
        builder: (context, m, _) {
          final providers = {for (final x in m.list) x.provider};
          // the models last used first, the current one with them; the others behind "More models"
          final recent = [
            for (final id in {widget.current, ...settings.recentModels}) ?m.list.where((x) => x.id == id).firstOrNull,
          ].take(5).toList();
          final grouped = all || recent.isEmpty;
          // a model known not to think has no effort to pick
          final thinks = m.list.where((x) => x.id == widget.current).firstOrNull?.reasoning ?? true;
          final note = switch (m) {
            (list: [], loading: true, error: _) => const Center(child: CupertinoActivityIndicator()),
            (list: [], loading: _, error: final String e) => Text(e, textAlign: TextAlign.center),
            (list: [], loading: _, error: _) => Text(l.modelsNone, textAlign: TextAlign.center),
            _ => null,
          };
          Widget group(List<Widget> rows) => Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: c.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: [
                for (final (i, r) in rows.indexed) ...[
                  if (i > 0) Divider(height: 1, indent: 16, color: c.outline.withValues(alpha: .15)),
                  r,
                ],
              ],
            ),
          );
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    l.model,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.onSurface),
                  ),
                  // refreshing an already shown list
                  if (m.loading && m.list.isNotEmpty) ...[const SizedBox(width: 8), const CupertinoActivityIndicator(radius: 8)],
                ],
              ),
              if (thinks)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(l.effort.toUpperCase(), style: TextStyle(fontSize: 13, color: c.outline)),
                          ),
                          Text(
                            effortText(l, effort),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: effort.isEmpty ? c.onSurface : effortColor(efforts.indexOf(effort) / (efforts.length - 1)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _EffortBar(
                        effort: effort,
                        onChanged: (e) {
                          settings.haptic();
                          setState(() => effort = e);
                          widget.onEffort(e);
                        },
                      ),
                      const SizedBox(height: 6),
                      // the ends of the bar
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            for (final e in [efforts.first, efforts.last])
                              Text(effortText(l, e), style: TextStyle(fontSize: 12, color: c.outline)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              if (note != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 32, 32, 48),
                  child: DefaultTextStyle.merge(
                    style: TextStyle(fontSize: 15, color: c.outline),
                    child: note,
                  ),
                ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    if (widget.allowDefault && note == null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: group([_ModelRow(name: l.cronServerDefault, id: '', selected: widget.current.isEmpty)]),
                      ),
                    if (recent.isNotEmpty && note == null) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                        child: Text(l.modelsRecent.toUpperCase(), style: TextStyle(fontSize: 13, color: c.outline)),
                      ),
                      group([
                        for (final x in recent) _ModelRow(name: x.name, detail: x.provider, id: x.id, selected: x.id == widget.current),
                        if (!grouped)
                          InkWell(
                            onTap: () => setState(() => all = true),
                            highlightColor: c.onSurface.withValues(alpha: .06),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      l.modelsMore,
                                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: c.primary),
                                    ),
                                  ),
                                  Icon(CupertinoIcons.chevron_down, size: 15, color: c.outline),
                                ],
                              ),
                            ),
                          ),
                      ]),
                    ],
                    if (grouped)
                      for (final p in providers) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 10,
                                backgroundColor: c.onSurface,
                                child: Text(
                                  p.isEmpty ? '' : p[0].toUpperCase(),
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.surface),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                p,
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.outline),
                              ),
                            ],
                          ),
                        ),
                        group([
                          for (final x in m.list.where((x) => x.provider == p))
                            _ModelRow(name: x.name, id: x.id, selected: x.id == widget.current),
                        ]),
                      ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The bar's colors, from the least effort to the most.
const _effortColors = [Color(0xFF34C7F0), Color(0xFF7C5CFF), Color(0xFFF2509A), Color(0xFFFF9F0A)];

/// The bar's color at [t] (0 to 1) along it.
Color effortColor(double t) {
  final x = t.clamp(0.0, 1.0) * (_effortColors.length - 1);
  final i = x.floor().clamp(0, _effortColors.length - 2);
  return Color.lerp(_effortColors[i], _effortColors[i + 1], x - i)!;
}

/// The reasoning effort as a thick bar filled to the level picked, tapped or dragged; sparks drift through it,
/// more and faster the harder Hermes thinks (still when the system asks for less motion).
class _EffortBar extends StatefulWidget {
  const _EffortBar({required this.effort, required this.onChanged});
  final String effort;
  final ValueChanged<String> onChanged;

  @override
  State<_EffortBar> createState() => _EffortBarState();
}

class _EffortBarState extends State<_EffortBar> with SingleTickerProviderStateMixin {
  final phase = ValueNotifier(0.0); // how far the sparks have drifted, in pixels
  late final ticker = createTicker(tick);
  var last = Duration.zero;

  int get level => efforts.indexOf(widget.effort).clamp(0, efforts.length - 1);

  void tick(Duration now) {
    phase.value += (now - last).inMicroseconds / 1e6 * (10 + level * 16);
    last = now;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      ticker.stop();
    } else if (!ticker.isActive) {
      last = Duration.zero;
      ticker.start();
    }
  }

  @override
  void dispose() {
    ticker.dispose();
    phase.dispose();
    super.dispose();
  }

  void pick(int i) {
    final e = efforts[i.clamp(0, efforts.length - 1)];
    if (e != widget.effort) widget.onChanged(e);
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    return Semantics(
      slider: true,
      label: l.effort,
      value: effortText(l, widget.effort),
      increasedValue: effortText(l, efforts[(level + 1).clamp(0, efforts.length - 1)]),
      decreasedValue: effortText(l, efforts[(level - 1).clamp(0, efforts.length - 1)]),
      onIncrease: () => pick(level + 1),
      onDecrease: () => pick(level - 1),
      child: LayoutBuilder(
        builder: (context, box) {
          const h = 34.0;
          final w = box.maxWidth;
          int at(Offset p) => ((p.dx - h / 2) / (w - h) * (efforts.length - 1)).round();
          return MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              key: const ValueKey('effort'),
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => pick(at(d.localPosition)),
              onHorizontalDragUpdate: (d) => pick(at(d.localPosition)),
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: level / (efforts.length - 1)),
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                builder: (context, fill, _) => CustomPaint(
                  size: Size(w, h),
                  painter: _EffortPainter(fill: fill, level: level, phase: phase, colors: c),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A spark's place along and across the bar (0 to 1), size, and speed and twinkle against the others'.
final _sparks = [
  for (var i = 0, seed = 7; i < 48; i++)
    (
      x: (seed = (seed * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff,
      y: (seed = (seed * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff,
      size: 1 + 2.2 * (seed = (seed * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff,
      speed: .5 + (seed = (seed * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff,
      twinkle: 6.28 * (seed = (seed * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff,
    ),
];

class _EffortPainter extends CustomPainter {
  _EffortPainter({required this.fill, required this.level, required this.phase, required this.colors}) : super(repaint: phase);
  final double fill; // 0 (auto) to 1 (max), animated between levels
  final int level;
  final ValueNotifier<double> phase;
  final ColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height, r = Radius.circular(h / 2);
    final steps = efforts.length - 1;
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, r), Paint()..color = colors.surfaceContainerHighest);
    // a dot for each level, under the fill
    for (var i = 0; i <= steps; i++) {
      canvas.drawCircle(Offset(h / 2 + (size.width - h) * i / steps, h / 2), 2.5, Paint()..color = colors.outline.withValues(alpha: .45));
    }
    final width = h + (size.width - h) * fill;
    final bar = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, width, h), r);
    // the colors span the whole track, the fill showing as far as it goes: warmer the higher
    final glow = Paint()..shader = const LinearGradient(colors: _effortColors).createShader(Offset.zero & size);
    canvas
      ..save()
      ..clipRRect(bar)
      ..drawRRect(bar, glow);
    // sparks drifting right, wrapping within the fill, twinkling
    final spark = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2);
    final t = phase.value;
    for (final p in _sparks.take(8 + level * 6)) {
      final x = (p.x * width + t * p.speed) % (width + 8) - 4;
      final y = 5 + p.y * (h - 10);
      final a = (.35 + .1 * level) * (.6 + .4 * math.sin(t / 9 + p.twinkle));
      canvas.drawCircle(Offset(x, y), p.size, spark..color = Colors.white.withValues(alpha: a.clamp(0, 1)));
    }
    canvas.restore();
    // the knob, at the fill's end
    canvas
      ..drawCircle(Offset(width - h / 2, h / 2 + 1), h / 2 - 4, Paint()..color = Colors.black.withValues(alpha: .18))
      ..drawCircle(Offset(width - h / 2, h / 2), h / 2 - 5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_EffortPainter old) => old.fill != fill || old.level != level || old.colors != colors;
}

class _ModelRow extends StatelessWidget {
  const _ModelRow({required this.name, required this.id, required this.selected, this.detail = ''});
  final String name, id, detail; // detail: its provider, among others'
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => Navigator.of(context).pop(id),
      highlightColor: c.onSurface.withValues(alpha: .06),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                name,
                style: TextStyle(fontSize: 16, fontWeight: selected ? FontWeight.w600 : FontWeight.w500, color: c.onSurface),
              ),
            ),
            if (detail.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Text(detail, style: TextStyle(fontSize: 13, color: c.outline)),
              ),
            AnimatedOpacity(
              opacity: selected ? 1 : 0,
              duration: const Duration(milliseconds: 150),
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle),
                child: Icon(CupertinoIcons.checkmark, size: 13, color: c.onPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A job's model as the picker names it ('provider/model'), '' for the server's default.
String jobModel(Map raw) => switch ((raw['provider'], raw['model'])) {
  (final String p, final String m) when p.isNotEmpty && m.isNotEmpty => '$p/$m',
  (_, final String m) => m,
  _ => '',
};

/// The job updates for a [showModelSheet] pick ('' back to the server's default).
Map<String, Object?> jobModelUpdates(String id) =>
    id.contains('/') ? {'provider': id.substring(0, id.indexOf('/')), 'model': modelName(id)} : {'model': null, 'provider': null};

/// A list row with a job's model and effort; a tap opens [showModelSheet], the server's default included.
class ModelTile extends StatefulWidget {
  const ModelTile({super.key, required this.model, required this.effort, required this.onModel, required this.onEffort, this.none});
  final String model, effort;
  final String? none; // what no model means, the server's default unless told
  final ValueChanged<String> onModel, onEffort;

  @override
  State<ModelTile> createState() => _ModelTileState();
}

class _ModelTileState extends State<ModelTile> {
  final models = ValueNotifier<Models>((list: const [], loading: false, error: null));

  @override
  void dispose() {
    models.dispose();
    super.dispose();
  }

  Future<void> pick() async {
    loadServerModels(models, AppLocalizations.of(context));
    final id = await showModelSheet(
      context,
      models: models,
      current: widget.model,
      effort: widget.effort,
      onEffort: widget.onEffort,
      allowDefault: true,
    );
    if (id != null && id != widget.model) widget.onModel(id);
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    return Hover(
      radius: 0,
      child: CupertinoListTile(
        title: Text(l.model, style: TextStyle(fontSize: 16, color: c.onSurface)),
        additionalInfo: Text(
          [
            widget.model.isEmpty ? widget.none ?? l.cronServerDefault : modelName(widget.model),
            if (widget.effort.isNotEmpty) effortText(l, widget.effort),
          ].join(' · '),
          style: TextStyle(fontSize: 13, color: c.outline),
        ),
        trailing: Icon(CupertinoIcons.chevron_forward, size: 18, color: c.outline),
        onTap: pick,
      ),
    );
  }
}

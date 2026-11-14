import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'hermes.dart';
import 'l10n/app_localizations.dart';
import 'settings.dart';

/// Has the server draw a picture from a description (`image.generate`); pops it as an attachment for the
/// next message, and saves it on a computer.
class ImageSheet extends StatefulWidget {
  const ImageSheet({super.key});

  @override
  State<ImageSheet> createState() => _ImageSheetState();
}

class _ImageSheetState extends State<ImageSheet> {
  final prompt = TextEditingController();
  var shape = 'square';
  var busy = false;
  Uint8List? image;
  String? error;

  @override
  void dispose() {
    prompt.dispose();
    super.dispose();
  }

  Future<void> make() async {
    if (prompt.text.trim().isEmpty || busy) return;
    final l = AppLocalizations.of(context);
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final g = await gateway();
      if (g == null) throw StateError('no server');
      // a picture takes a while: up to a few minutes
      final r = await g.call('image.generate', {'prompt': prompt.text.trim(), 'aspect_ratio': shape}, const Duration(minutes: 4));
      final data = '${r['image_data'] ?? ''}';
      if (r['success'] != true || !data.contains(',')) throw HttpException('${r['error'] ?? l.imageFailed}');
      image = base64Decode(data.substring(data.indexOf(',') + 1));
    } catch (e) {
      error = e is HttpException ? e.message : serverErrorText(l, e is StateError ? null : e);
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> save() async {
    final to = await getSaveLocation(suggestedName: 'hermes-image.png');
    if (to != null) await File(to.path).writeAsBytes(image!);
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    final computer = (!kIsWeb && Platform.isMacOS) || (!kIsWeb && Platform.isLinux) || (!kIsWeb && Platform.isWindows);
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l.imageCreate,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: c.onSurface),
            ),
            const SizedBox(height: 14),
            CupertinoTextField(
              controller: prompt,
              autofocus: true,
              minLines: 2,
              maxLines: 5,
              placeholder: l.imagePrompt,
              padding: const EdgeInsets.all(12),
              style: TextStyle(color: c.onSurface),
              decoration: BoxDecoration(color: c.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            CupertinoSlidingSegmentedControl<String>(
              groupValue: shape,
              onValueChanged: (v) => setState(() => shape = v ?? shape),
              children: {'square': Text(l.imageSquare), 'landscape': Text(l.imageLandscape), 'portrait': Text(l.imagePortrait)},
            ),
            const SizedBox(height: 16),
            if (busy)
              Column(
                children: [
                  const CupertinoActivityIndicator(radius: 14),
                  const SizedBox(height: 8),
                  Text(l.imageMaking, style: TextStyle(fontSize: 13, color: c.outline)),
                ],
              )
            else if (image case final img?) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(img, fit: BoxFit.contain),
              ),
              const SizedBox(height: 12),
              CupertinoButton.filled(
                onPressed: () => Navigator.pop<Attachment>(context, (name: 'hermes-image.png', bytes: img, image: true)),
                child: Text(l.imageAttach),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CupertinoButton(onPressed: make, child: Text(l.imageAgain)),
                  if (computer) CupertinoButton(onPressed: save, child: Text(l.imageSave)),
                ],
              ),
            ] else
              CupertinoButton.filled(onPressed: prompt.text.trim().isEmpty ? null : make, child: Text(l.imageMake)),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: CupertinoColors.systemRed),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

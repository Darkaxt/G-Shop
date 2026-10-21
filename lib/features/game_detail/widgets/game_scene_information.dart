import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Game facts over the inspected 3D media, with the scene still visible below.
class GameSceneInformation extends StatelessWidget {
  final String title;
  final String? summary, credits, genres, score, referenceNote;
  final VoidCallback onClose;
  const GameSceneInformation(
      {super.key,
      required this.title,
      required this.onClose,
      this.summary,
      this.credits,
      this.genres,
      this.score,
      this.referenceNote});

  @override
  Widget build(BuildContext context) => SafeArea(
      child: Padding(
          padding: const EdgeInsets.all(16),
          child: Align(
              alignment: Alignment.center,
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: BackdropFilter(
                          filter: ui.ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                          child: Material(
                              color: const Color(0xB3161113),
                              borderRadius: BorderRadius.circular(16),
                              clipBehavior: Clip.antiAlias,
                              child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Row(children: [
                                          Expanded(
                                              child: Text(title,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleLarge)),
                                          IconButton(
                                              tooltip: 'Close game information',
                                              onPressed: onClose,
                                              constraints: const BoxConstraints(
                                                  minWidth: 44, minHeight: 44),
                                              icon: const Icon(Icons.close)),
                                        ]),
                                        Flexible(
                                            child: SingleChildScrollView(
                                                child: Align(
                                                    alignment:
                                                        Alignment.topLeft,
                                                    child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          if (score
                                                                  ?.isNotEmpty ==
                                                              true) ...[
                                                            Text(score!,
                                                                style: Theme.of(
                                                                        context)
                                                                    .textTheme
                                                                    .titleMedium),
                                                            const SizedBox(
                                                                height: 12),
                                                          ],
                                                          if (credits
                                                                  ?.isNotEmpty ==
                                                              true) ...[
                                                            Text(credits!),
                                                            const SizedBox(
                                                                height: 8),
                                                          ],
                                                          if (genres
                                                                  ?.isNotEmpty ==
                                                              true) ...[
                                                            Text(genres!,
                                                                style: const TextStyle(
                                                                    color: Colors
                                                                        .white70)),
                                                            const SizedBox(
                                                                height: 16),
                                                          ],
                                                          Text(
                                                              summary?.isNotEmpty ==
                                                                      true
                                                                  ? summary!
                                                                  : 'No description yet.',
                                                              style:
                                                                  const TextStyle(
                                                                      height:
                                                                          1.5)),
                                                          if (referenceNote !=
                                                              null) ...[
                                                            const SizedBox(
                                                                height: 20),
                                                            Text(referenceNote!,
                                                                style: const TextStyle(
                                                                    color: Colors
                                                                        .white70,
                                                                    fontSize:
                                                                        12)),
                                                          ],
                                                        ])))),
                                      ])))))))));
}

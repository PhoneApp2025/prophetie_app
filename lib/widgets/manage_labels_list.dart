import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../main.dart';
import 'dart:math' as math;

bool isLabelNameValid(String name) {
  final forbidden = RegExp(r'[/.\\\[\]#\$]');
  return !forbidden.hasMatch(name);
}

class ManageLabelsList extends StatefulWidget {
  final List<String> labels;
  final void Function(List<String>) onReorder;
  final void Function(String oldLabel, String newLabel) onRename;
  final void Function(String) onDelete;
  final void Function(String) onAddLabel;
  final bool showTitle;

  const ManageLabelsList({
    Key? key,
    required this.labels,
    required this.onReorder,
    required this.onRename,
    required this.onDelete,
    required this.onAddLabel,
    this.showTitle = false,
  }) : super(key: key);

  @override
  _ManageLabelsListState createState() => _ManageLabelsListState();
}

class _ManageLabelsListState extends State<ManageLabelsList> {
  final TextEditingController _addLabelController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String? _editingLabel; // null = kein Inline-Edit aktiv

  @override
  void dispose() {
    _addLabelController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showTitle)
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 6),
            child: Center(
              child: Text(
                'Labels verwalten',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ),

        // Suche
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: SizedBox(
            height: 40,
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Suchen…',
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                filled: true,
                fillColor: Theme.of(context).brightness == Brightness.dark
                    ? Colors.grey[850]
                    : Colors.grey[200],
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Neues Label hinzufügen
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _addLabelController,
                    decoration: InputDecoration(
                      hintText: 'Neues Label eingeben',
                      prefixIcon: const Icon(
                        Icons.local_offer_outlined,
                        size: 18,
                      ),
                      isDense: true,
                      filled: true,
                      fillColor: Theme.of(context).brightness == Brightness.dark
                          ? Colors.grey[850]
                          : Colors.grey[200],
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) {
                      final value = _addLabelController.text.trim();
                      if (value.isNotEmpty) {
                        if (!isLabelNameValid(value)) {
                          showFlushbar(
                            'Labels dürfen kein /, \\, [, ], #, \$ oder . enthalten.',
                          );
                          return;
                        }
                        widget.onAddLabel(value);
                        _addLabelController.clear();
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 40,
                width: 40,
                child: Material(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey[850]
                      : Colors.grey[200],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      final value = _addLabelController.text.trim();
                      if (value.isNotEmpty) {
                        if (!isLabelNameValid(value)) {
                          showFlushbar(
                            'Labels dürfen kein /, \\, [, ], #, \$ oder . enthalten.',
                          );
                          return;
                        }
                        widget.onAddLabel(value);
                        _addLabelController.clear();
                      }
                    },
                    child: const Center(
                      child: Icon(
                        Icons.add,
                        size: 20,
                        color: Color(0xFFFF2C55),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Kein Suchmodus: Reorderable List auf Basis der gefilterten Liste
        SizedBox(
          height: 360,
          child: Builder(
            builder: (context) {
              // Kein Suchmodus: Reorderable List auf Basis der gefilterten Liste
              final base = _filtered(
                context,
              ); // bei leerer Suche == widget.labels
              return ReorderableListView.builder(
                shrinkWrap: true,
                buildDefaultDragHandles: false,
                itemCount: base.length,
                onReorder: (oldIndex, newIndex) {
                  // Mappe Reorder-Indices (aus gefilterter Sicht) auf Original-Liste
                  final updated = [...widget.labels];
                  final originalOld = widget.labels.indexOf(base[oldIndex]);
                  if (newIndex > oldIndex) newIndex--;
                  final originalNew = newIndex < base.length
                      ? widget.labels.indexOf(base[newIndex])
                      : widget.labels.length;
                  final item = updated.removeAt(originalOld);
                  updated.insert(math.min(originalNew, updated.length), item);
                  widget.onReorder(updated);
                  setState(() {});
                },
                itemBuilder: (context, index) {
                  final label = base[index];
                  return Dismissible(
                    key: ValueKey('dismiss_$label'),
                    direction: DismissDirection.endToStart,
                    background: _SwipeBg(color: Colors.redAccent),
                    onDismissed: (_) async {
                      final firestore = FirebaseFirestore.instance;
                      final uid = FirebaseAuth.instance.currentUser!.uid;

                      final dreams = await firestore
                          .collection('users')
                          .doc(uid)
                          .collection('traeume')
                          .where('labels', arrayContains: label)
                          .get();
                      for (final doc in dreams.docs) {
                        await doc.reference.update({
                          'labels': FieldValue.arrayRemove([label]),
                        });
                      }

                      final props = await firestore
                          .collection('users')
                          .doc(uid)
                          .collection('prophetien')
                          .where('labels', arrayContains: label)
                          .get();
                      for (final doc in props.docs) {
                        await doc.reference.update({
                          'labels': FieldValue.arrayRemove([label]),
                        });
                      }

                      widget.onDelete(label);
                      showFlushbar(
                        'Label wurde entfernt. Einträge wurden aktualisiert.',
                      );
                    },
                    child: _LabelRow(
                      key: ValueKey('row_$label'),
                      label: label,
                      isEditing: _editingLabel == label,
                      onStartEdit: () => setState(() => _editingLabel = label),
                      onCancelEdit: () => setState(() => _editingLabel = null),
                      onSubmitEdit: (newValue) async {
                        if (newValue == null ||
                            newValue.trim().isEmpty ||
                            newValue == label) {
                          setState(() => _editingLabel = null);
                          return;
                        }
                        if (!isLabelNameValid(newValue)) {
                          showFlushbar(
                            'Labels dürfen kein /, \\, [, ], #, \$ oder . enthalten.',
                          );
                          return;
                        }
                        final firestore = FirebaseFirestore.instance;
                        final uid = FirebaseAuth.instance.currentUser!.uid;

                        final dreams = await firestore
                            .collection('users')
                            .doc(uid)
                            .collection('traeume')
                            .where('labels', arrayContains: label)
                            .get();
                        for (final doc in dreams.docs) {
                          await doc.reference.update({
                            'labels': FieldValue.arrayRemove([label]),
                          });
                          await doc.reference.update({
                            'labels': FieldValue.arrayUnion([newValue]),
                          });
                        }

                        final props = await firestore
                            .collection('users')
                            .doc(uid)
                            .collection('prophetien')
                            .where('labels', arrayContains: label)
                            .get();
                        for (final doc in props.docs) {
                          await doc.reference.update({
                            'labels': FieldValue.arrayRemove([label]),
                          });
                          await doc.reference.update({
                            'labels': FieldValue.arrayUnion([newValue]),
                          });
                        }

                        widget.onRename(label, newValue);
                        setState(() => _editingLabel = null);
                      },
                      dragHandle: ReorderableDragStartListener(
                        index: index,
                        child: Icon(
                          Icons.drag_indicator,
                          color: Colors.grey.shade500,
                          size: 18,
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

extension on _ManageLabelsListState {
  List<String> _filtered(BuildContext context) {
    if (_query.isEmpty) return widget.labels;
    return widget.labels
        .where((l) => l.toLowerCase().contains(_query))
        .toList();
  }
}

class _SwipeBg extends StatelessWidget {
  final Color color;
  const _SwipeBg({required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [color.withOpacity(0.2), color.withOpacity(0.6)],
        ),
      ),
      child: const Icon(Icons.delete, color: Colors.white),
    );
  }
}

class _LabelRow extends StatelessWidget {
  final String label;
  final bool isEditing;
  final VoidCallback onStartEdit;
  final VoidCallback onCancelEdit;
  final ValueChanged<String?> onSubmitEdit;
  final Widget dragHandle;
  const _LabelRow({
    super.key,
    required this.label,
    required this.isEditing,
    required this.onStartEdit,
    required this.onCancelEdit,
    required this.onSubmitEdit,
    required this.dragHandle,
  });

  @override
  Widget build(BuildContext context) {
    final bg = Colors.transparent;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: const BoxDecoration(color: Colors.transparent),
      child: Row(
        children: [
          dragHandle,
          const SizedBox(width: 6),
          Expanded(
            child: isEditing
                ? TextField(
                    autofocus: true,
                    controller: TextEditingController(text: label),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Theme.of(context).brightness == Brightness.dark
                          ? Colors.grey[850]
                          : Colors.grey[200],
                    ),
                    style: const TextStyle(fontSize: 14, height: 1.0),
                    onSubmitted: onSubmitEdit,
                  )
                : Text(
                    label,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(height: 1.0),
                  ),
          ),
          const SizedBox(width: 8),
          if (!isEditing)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: onStartEdit,
              tooltip: 'Umbenennen',
              iconSize: 18,
              visualDensity: VisualDensity.compact,
            ),
          if (isEditing)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: onCancelEdit,
              tooltip: 'Abbrechen',
              iconSize: 18,
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

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

  @override
  void dispose() {
    _addLabelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showTitle)
          Column(
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Center(
                child: Text(
                  'Labels verwalten',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _addLabelController,
                        decoration: InputDecoration(
                          hintText: 'Neues Label eingeben',
                          filled: true,
                          fillColor:
                              Theme.of(context).brightness == Brightness.dark
                              ? Colors.grey[800]
                              : Colors.grey[200],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: () {
                        final value = _addLabelController.text.trim();
                        if (value.isNotEmpty) {
                          widget.onAddLabel(value);
                          _addLabelController.clear();
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const SizedBox(height: 12),
            ],
          ),
        SizedBox(
          height: 300,
          child: ReorderableListView(
            shrinkWrap: true,
            buildDefaultDragHandles: true,
            children: [
              for (final label in widget.labels)
                ListTile(
                  key: ValueKey(label),
                  title: Text(label),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () async {
                          final newValue = await showDialog<String>(
                            context: context,
                            builder: (context) {
                              final controller = TextEditingController(
                                text: label,
                              );
                              return AlertDialog(
                                title: const Text('Label umbenennen'),
                                content: TextField(controller: controller),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.of(
                                      context,
                                    ).pop(controller.text),
                                    child: const Text('Speichern'),
                                  ),
                                ],
                              );
                            },
                          );
                          if (newValue != null &&
                              newValue.isNotEmpty &&
                              newValue != label) {
                            widget.onRename(label, newValue);
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () => widget.onDelete(label),
                      ),
                    ],
                  ),
                ),
            ],
            onReorder: (oldIndex, newIndex) {
              final updated = [...widget.labels];
              if (oldIndex < newIndex) newIndex--;
              final item = updated.removeAt(oldIndex);
              updated.insert(newIndex, item);
              widget.onReorder(updated);
            },
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

/// Opens a bottom sheet with a search box and returns the chosen item,
/// or null if the user closes it. Works well even with hundreds of items.
Future<String?> pickFromList(
  BuildContext context, {
  required String title,
  required List<String> items,
  String? selected,
}) {
  final sorted = [...items]
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      var query = '';
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          final q = query.trim().toLowerCase();
          final shown = q.isEmpty
              ? sorted
              : sorted.where((e) => e.toLowerCase().contains(q)).toList();
          final height = MediaQuery.of(ctx).size.height * 0.75;
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: SizedBox(
              height: height,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: TextField(
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Search',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: query.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () => setLocal(() => query = ''),
                              ),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (v) => setLocal(() => query = v),
                    ),
                  ),
                  Expanded(
                    child: shown.isEmpty
                        ? const Center(child: Text('Nothing found.'))
                        : ListView.builder(
                            itemCount: shown.length,
                            itemBuilder: (_, i) {
                              final name = shown[i];
                              return ListTile(
                                title: Text(name),
                                trailing: name == selected
                                    ? const Icon(Icons.check, color: Color(0xFF0D47A1))
                                    : null,
                                onTap: () => Navigator.pop(ctx, name),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

/// Looks like a dropdown field, but opens the searchable list when tapped.
class PickerField extends StatelessWidget {
  const PickerField({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.arrow_drop_down),
        ),
        child: Text(
          value.isEmpty ? 'Tap to choose' : value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

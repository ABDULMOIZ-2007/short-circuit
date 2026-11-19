import 'package:flutter/material.dart';
import 'project_view.dart';
import 'design_system.dart';

class ComponentLibrary extends StatefulWidget {
  const ComponentLibrary({super.key});
  @override
  State<ComponentLibrary> createState() => _ComponentLibraryState();
}

class _ComponentLibraryState extends State<ComponentLibrary> {
  String query = '', category = 'All';
  @override
  Widget build(BuildContext context) {
    final types = componentNames.keys
        .where(
          (t) =>
              (category == 'All' || componentCategories[t] == category) &&
              (componentNames[t]!.toLowerCase().contains(query.toLowerCase()) ||
                  componentDescriptions[t]!.toLowerCase().contains(
                    query.toLowerCase(),
                  )),
        )
        .toList();
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .84,
        child: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 8, 18),
                child: Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Components',
                            style: TextStyle(
                              fontSize: 25,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -.8,
                            ),
                          ),
                          SizedBox(height: 5),
                          Text(
                            'Choose a part to place on the schematic.',
                            style: TextStyle(color: muted, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      tooltip: 'Close library',
                      icon: const Icon(Icons.close, size: 20),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  key: const ValueKey('component-search'),
                  onChanged: (s) => setState(() => query = s),
                  decoration: const InputDecoration(
                    hintText: 'Find a component',
                    prefixIcon: Icon(Icons.search, size: 19),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    for (final group in const [
                      'All',
                      'Passives',
                      'Sources',
                      'Semiconductors',
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 7),
                        child: TextButton(
                          onPressed: () => setState(() => category = group),
                          style: TextButton.styleFrom(
                            foregroundColor: category == group
                                ? canvasDark
                                : muted,
                            backgroundColor: category == group ? accent : panel,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 9,
                            ),
                          ),
                          child: Text(
                            group,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: types.isEmpty
                    ? const Center(
                        child: Text(
                          'No matching components',
                          style: TextStyle(color: muted),
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 250,
                          mainAxisExtent: scale > 1.2 ? 160 : 127,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                        itemCount: types.length,
                        itemBuilder: (context, index) {
                          final type = types[index];
                          return Material(
                            color: panel,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: const BorderSide(color: edge),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              key: ValueKey('part-$type'),
                              onTap: () => Navigator.pop(context, type),
                              child: Padding(
                                padding: const EdgeInsets.all(13),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        SymbolPreview(
                                          type,
                                          size: 38,
                                          color: partColor(type),
                                        ),
                                        const Spacer(),
                                        Text(
                                          '${pinCount(type)}P',
                                          style: technical(size: 8),
                                        ),
                                      ],
                                    ),
                                    const Spacer(),
                                    Text(
                                      componentNames[type]!,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            type == 'ground'
                                                ? 'Reference'
                                                : type == 'switch'
                                                ? 'Interactive'
                                                : engineering(
                                                    componentDefaults[type]!,
                                                    componentUnits[type] ?? '',
                                                  ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: technical(size: 9),
                                          ),
                                        ),
                                        const Icon(
                                          Icons.add,
                                          size: 15,
                                          color: muted,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

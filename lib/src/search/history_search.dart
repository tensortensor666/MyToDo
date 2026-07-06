import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' as material;

import '../data/todo_models.dart';

typedef TodoHistoryItemBuilder =
    Widget Function(BuildContext context, TodoItem todo);
typedef TodoHistorySearch = List<TodoItem> Function(String query);

enum HistoryFilter { all, active, completed, deleted }

class TodoHistorySearchDelegate extends material.SearchDelegate<void> {
  TodoHistorySearchDelegate({
    required this.listenable,
    required this.searchTodos,
    required this.itemBuilder,
  });

  final Listenable listenable;
  final TodoHistorySearch searchTodos;
  final TodoHistoryItemBuilder itemBuilder;
  HistoryFilter _filter = HistoryFilter.all;

  @override
  String get searchFieldLabel => '搜索历史';

  @override
  List<material.Widget> buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        material.IconButton(
          tooltip: '清除',
          onPressed: () => query = '',
          icon: const material.Icon(material.Icons.clear),
        ),
    ];
  }

  @override
  material.Widget buildLeading(BuildContext context) {
    return material.IconButton(
      tooltip: '返回',
      onPressed: () => close(context, null),
      icon: const material.Icon(material.Icons.arrow_back),
    );
  }

  @override
  material.Widget buildResults(BuildContext context) {
    return _TodoHistorySearchDelegateBody(
      listenable: listenable,
      searchTodos: searchTodos,
      query: query,
      filter: _filter,
      itemBuilder: itemBuilder,
      onFilterChanged: (filter) {
        _filter = filter;
        showResults(context);
      },
    );
  }

  @override
  material.Widget buildSuggestions(BuildContext context) {
    return _TodoHistorySearchDelegateBody(
      listenable: listenable,
      searchTodos: searchTodos,
      query: query,
      filter: _filter,
      itemBuilder: itemBuilder,
      onFilterChanged: (filter) {
        _filter = filter;
        showSuggestions(context);
      },
    );
  }
}

class _TodoHistorySearchDelegateBody extends StatelessWidget {
  const _TodoHistorySearchDelegateBody({
    required this.listenable,
    required this.searchTodos,
    required this.query,
    required this.filter,
    required this.itemBuilder,
    required this.onFilterChanged,
  });

  final Listenable listenable;
  final TodoHistorySearch searchTodos;
  final String query;
  final HistoryFilter filter;
  final TodoHistoryItemBuilder itemBuilder;
  final ValueChanged<HistoryFilter> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    return material.AnimatedBuilder(
      animation: listenable,
      builder: (context, _) {
        final normalizedQuery = query.trim();
        final todos = searchTodos(normalizedQuery)
            .where((todo) => _matchesHistoryFilter(todo, filter))
            .toList(growable: false);
        return material.Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MaterialHistoryFilterBar(
              filter: filter,
              onFilterChanged: onFilterChanged,
            ),
            const material.Divider(height: 1),
            material.Expanded(
              child: todos.isEmpty
                  ? material.Center(
                      child: material.Text(
                        normalizedQuery.isEmpty ? '还没有历史' : '没有匹配的历史',
                      ),
                    )
                  : material.ListView.builder(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                      itemCount: todos.length,
                      itemBuilder: (context, index) {
                        return itemBuilder(context, todos[index]);
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _MaterialHistoryFilterBar extends StatelessWidget {
  const _MaterialHistoryFilterBar({
    required this.filter,
    required this.onFilterChanged,
  });

  final HistoryFilter filter;
  final ValueChanged<HistoryFilter> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    return material.SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: material.Row(
        children: [
          _MaterialFilterChip(
            label: '全部',
            value: HistoryFilter.all,
            groupValue: filter,
            onChanged: onFilterChanged,
          ),
          const material.SizedBox(width: 8),
          _MaterialFilterChip(
            label: '当前',
            value: HistoryFilter.active,
            groupValue: filter,
            onChanged: onFilterChanged,
          ),
          const material.SizedBox(width: 8),
          _MaterialFilterChip(
            label: '已完成',
            value: HistoryFilter.completed,
            groupValue: filter,
            onChanged: onFilterChanged,
          ),
          const material.SizedBox(width: 8),
          _MaterialFilterChip(
            label: '已删除',
            value: HistoryFilter.deleted,
            groupValue: filter,
            onChanged: onFilterChanged,
          ),
        ],
      ),
    );
  }
}

class _MaterialFilterChip extends StatelessWidget {
  const _MaterialFilterChip({
    required this.label,
    required this.value,
    required this.groupValue,
    required this.onChanged,
  });

  final String label;
  final HistoryFilter value;
  final HistoryFilter groupValue;
  final ValueChanged<HistoryFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return material.ChoiceChip(
      label: material.Text(label),
      selected: value == groupValue,
      onSelected: (_) => onChanged(value),
    );
  }
}

class TodoHistorySearchResults extends StatefulWidget {
  const TodoHistorySearchResults({
    super.key,
    required this.listenable,
    required this.searchTodos,
    required this.query,
    required this.initialFilter,
    required this.itemBuilder,
    required this.onFilterChanged,
  });

  final Listenable listenable;
  final TodoHistorySearch searchTodos;
  final String query;
  final HistoryFilter initialFilter;
  final TodoHistoryItemBuilder itemBuilder;
  final ValueChanged<HistoryFilter> onFilterChanged;

  @override
  State<TodoHistorySearchResults> createState() =>
      _TodoHistorySearchResultsState();
}

class _TodoHistorySearchResultsState extends State<TodoHistorySearchResults> {
  late HistoryFilter _filter = widget.initialFilter;

  @override
  void didUpdateWidget(covariant TodoHistorySearchResults oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialFilter != widget.initialFilter) {
      _filter = widget.initialFilter;
    }
  }

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = widget.query.trim();
    final todos = widget
        .searchTodos(normalizedQuery)
        .where(_matchesFilter)
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HistoryFilterBar(filter: _filter, onFilterChanged: _changeFilter),
        const Divider(),
        Expanded(
          child: todos.isEmpty
              ? Center(
                  child: Text(normalizedQuery.isEmpty ? '还没有历史' : '没有匹配的历史'),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                  itemCount: todos.length,
                  itemBuilder: (context, index) {
                    return widget.itemBuilder(context, todos[index]);
                  },
                ),
        ),
      ],
    );
  }

  bool _matchesFilter(TodoItem todo) {
    return _matchesHistoryFilter(todo, _filter);
  }

  void _changeFilter(HistoryFilter filter) {
    if (_filter == filter) {
      return;
    }
    setState(() {
      _filter = filter;
    });
    widget.onFilterChanged(filter);
  }
}

bool _matchesHistoryFilter(TodoItem todo, HistoryFilter filter) {
  return switch (filter) {
    HistoryFilter.all => true,
    HistoryFilter.active => !todo.deleted && !todo.completed,
    HistoryFilter.completed => !todo.deleted && todo.completed,
    HistoryFilter.deleted => todo.deleted,
  };
}

class _HistoryFilterBar extends StatelessWidget {
  const _HistoryFilterBar({
    required this.filter,
    required this.onFilterChanged,
  });

  final HistoryFilter filter;
  final ValueChanged<HistoryFilter> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          _FilterChipButton(
            label: '全部',
            value: HistoryFilter.all,
            groupValue: filter,
            onChanged: onFilterChanged,
          ),
          const SizedBox(width: 8),
          _FilterChipButton(
            label: '当前',
            value: HistoryFilter.active,
            groupValue: filter,
            onChanged: onFilterChanged,
          ),
          const SizedBox(width: 8),
          _FilterChipButton(
            label: '已完成',
            value: HistoryFilter.completed,
            groupValue: filter,
            onChanged: onFilterChanged,
          ),
          const SizedBox(width: 8),
          _FilterChipButton(
            label: '已删除',
            value: HistoryFilter.deleted,
            groupValue: filter,
            onChanged: onFilterChanged,
          ),
        ],
      ),
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  const _FilterChipButton({
    required this.label,
    required this.value,
    required this.groupValue,
    required this.onChanged,
  });

  final String label;
  final HistoryFilter value;
  final HistoryFilter groupValue;
  final ValueChanged<HistoryFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final selected = value == groupValue;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => onChanged(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? theme.accentColor
                      .defaultBrushFor(theme.brightness)
                      .withValues(alpha: 0.12)
                : theme.resources.subtleFillColorTransparent,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? theme.accentColor.defaultBrushFor(theme.brightness)
                  : theme.resources.cardStrokeColorDefault,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? theme.accentColor.defaultBrushFor(theme.brightness)
                  : theme.resources.textFillColorSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

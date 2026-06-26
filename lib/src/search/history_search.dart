import 'package:flutter/material.dart';

import '../data/todo_models.dart';

typedef TodoHistoryItemBuilder =
    Widget Function(BuildContext context, TodoItem todo);
typedef TodoHistorySearch = List<TodoItem> Function(String query);

enum HistoryFilter { all, active, completed, deleted }

class TodoHistorySearchDelegate extends SearchDelegate<void> {
  TodoHistorySearchDelegate({
    required this.listenable,
    required this.searchTodos,
    required this.itemBuilder,
  }) : super(searchFieldLabel: '搜索历史');

  final Listenable listenable;
  final TodoHistorySearch searchTodos;
  final TodoHistoryItemBuilder itemBuilder;
  HistoryFilter _filter = HistoryFilter.all;

  @override
  List<Widget>? buildActions(BuildContext context) {
    if (query.isEmpty) {
      return null;
    }
    return [
      IconButton(
        tooltip: '清除',
        onPressed: () {
          query = '';
          showSuggestions(context);
        },
        icon: const Icon(Icons.close),
      ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      tooltip: '返回',
      onPressed: () => close(context, null),
      icon: const Icon(Icons.arrow_back),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return TodoHistorySearchResults(
      listenable: listenable,
      searchTodos: searchTodos,
      query: query,
      initialFilter: _filter,
      itemBuilder: itemBuilder,
      onFilterChanged: (filter) {
        _filter = filter;
      },
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return TodoHistorySearchResults(
      listenable: listenable,
      searchTodos: searchTodos,
      query: query,
      initialFilter: _filter,
      itemBuilder: itemBuilder,
      onFilterChanged: (filter) {
        _filter = filter;
      },
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
    return AnimatedBuilder(
      animation: widget.listenable,
      builder: (context, _) {
        final normalizedQuery = widget.query.trim();
        final todos = widget
            .searchTodos(normalizedQuery)
            .where(_matchesFilter)
            .toList(growable: false);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _HistoryFilterBar(filter: _filter, onFilterChanged: _changeFilter),
            const Divider(height: 1),
            Expanded(
              child: todos.isEmpty
                  ? Center(
                      child: Text(
                        normalizedQuery.isEmpty ? '还没有历史' : '没有匹配的历史',
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      itemCount: todos.length,
                      itemBuilder: (context, index) {
                        return widget.itemBuilder(context, todos[index]);
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  bool _matchesFilter(TodoItem todo) {
    return switch (_filter) {
      HistoryFilter.all => true,
      HistoryFilter.active => !todo.deleted && !todo.completed,
      HistoryFilter.completed => !todo.deleted && todo.completed,
      HistoryFilter.deleted => todo.deleted,
    };
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
    return ChoiceChip(
      label: Text(label),
      selected: value == groupValue,
      onSelected: (_) => onChanged(value),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:tukan/tukan.dart';

import '../services/services.dart';

TodoStatus _nextStatus(TodoStatus status) => switch (status) {
  TodoStatus.todo => TodoStatus.inProgress,
  TodoStatus.inProgress => TodoStatus.done,
  TodoStatus.done => TodoStatus.todo,
};

class TodosSection extends StatefulWidget {
  final AppServices appServices;

  const TodosSection({super.key, required this.appServices});

  @override
  State<TodosSection> createState() => _TodosSectionState();
}

class _TodosSectionState extends State<TodosSection> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  TodoStatus? _statusFilter;
  TodoPriority? _priorityFilter;
  TodoPriority _newPriority = TodoPriority.medium;

  bool _busy = false;
  List<Todo> _todos = const <Todo>[];
  int _total = 0;
  Todo? _selectedTodo;
  String? _notice;
  bool _isError = false;
  Map<String, String> _fieldErrors = const <String, String>{};

  @override
  void initState() {
    super.initState();
    _loadTodos();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadTodos() async {
    setState(() {
      _busy = true;
      _notice = null;
      _isError = false;
    });

    final String querySearch = _searchController.text.trim();
    final result = await widget.appServices.todos.list(
      status: _statusFilter,
      priority: _priorityFilter,
      search: querySearch.isEmpty ? null : querySearch,
    );

    if (!mounted) return;

    switch (result) {
      case ApiSuccess(:final data):
        setState(() {
          _busy = false;
          _todos = data.items;
          _total = data.total;
        });
      case ApiFailure(:final error):
        setState(() {
          _busy = false;
          _todos = const <Todo>[];
          _total = 0;
          _notice = error.message;
          _isError = true;
        });
    }
  }

  Future<void> _createTodo() async {
    setState(() {
      _busy = true;
      _fieldErrors = const <String, String>{};
      _notice = null;
      _isError = false;
    });

    final String trimmedDesc = _descriptionController.text.trim();
    final result = await widget.appServices.todos.create(
      title: _titleController.text,
      description: trimmedDesc.isEmpty ? null : trimmedDesc,
      priority: _newPriority,
    );

    if (!mounted) return;

    switch (result) {
      case ApiSuccess(:final data):
        _titleController.clear();
        _descriptionController.clear();
        setState(() {
          _selectedTodo = data;
          _notice = 'Created todo ${data.id}: ${data.title}';
          _isError = false;
        });
        await _loadTodos();
      case ApiFailure(:final error):
        if (error.body case final validation?) {
          setState(() {
            _busy = false;
            _fieldErrors = validation.fieldErrors;
            _notice = validation.message;
            _isError = true;
          });
          return;
        }
        setState(() {
          _busy = false;
          _notice = error.message;
          _isError = true;
        });
    }
  }

  Future<void> _inspectTodo(String todoId) async {
    final result = await widget.appServices.todos.getById(todoId);
    if (!mounted) return;

    switch (result) {
      case ApiSuccess(:final data):
        setState(() {
          _selectedTodo = data;
          _notice = null;
        });
      case ApiFailure(:final error):
        setState(() {
          _notice = error.body?.message ?? error.message;
          _isError = true;
        });
    }
  }

  Future<void> _cycleStatus(Todo todo) async {
    final result = await widget.appServices.todos.update(
      todo.id,
      status: _nextStatus(todo.status),
    );
    if (!mounted) return;

    switch (result) {
      case ApiSuccess(:final data):
        if (_selectedTodo?.id == data.id) {
          _selectedTodo = data;
        }
        await _loadTodos();
      case ApiFailure(:final error):
        setState(() {
          _notice =
              error.body?.validationErrorResponse?.message ??
              error.body?.apiErrorResponse?.message ??
              error.message;
          _isError = true;
        });
    }
  }

  Future<void> _deleteTodo(String todoId) async {
    final result = await widget.appServices.todos.remove(todoId);
    if (!mounted) return;

    switch (result) {
      case ApiSuccess():
        if (_selectedTodo?.id == todoId) {
          _selectedTodo = null;
        }
        await _loadTodos();
      case ApiFailure(:final error):
        setState(() {
          _notice = error.body?.message ?? error.message;
          _isError = true;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  'Todos ($_total)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                OutlinedButton(
                  onPressed: _busy ? null : _loadTodos,
                  child: const Text('Reload'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: 'New todo title (min 3 chars)',
                errorText: _fieldErrors['title'],
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _descriptionController,
              decoration: InputDecoration(
                labelText: 'Description (optional)',
                errorText: _fieldErrors['description'],
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                DropdownButton<TodoPriority>(
                  value: _newPriority,
                  items: TodoPriority.values
                      .map(
                        (TodoPriority p) => DropdownMenuItem<TodoPriority>(
                          value: p,
                          child: Text(p.value),
                        ),
                      )
                      .toList(),
                  onChanged: (TodoPriority? next) {
                    if (next != null) {
                      setState(() => _newPriority = next);
                    }
                  },
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _busy ? null : _createTodo,
                  child: const Text('Create Todo'),
                ),
              ],
            ),
            const Divider(height: 24),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                SizedBox(
                  width: 220,
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      labelText: 'Search',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _loadTodos(),
                  ),
                ),
                DropdownButton<TodoStatus?>(
                  value: _statusFilter,
                  hint: const Text('All statuses'),
                  items: <DropdownMenuItem<TodoStatus?>>[
                    const DropdownMenuItem<TodoStatus?>(
                      value: null,
                      child: Text('All statuses'),
                    ),
                    ...TodoStatus.values.map(
                      (TodoStatus s) => DropdownMenuItem<TodoStatus?>(
                        value: s,
                        child: Text(s.value),
                      ),
                    ),
                  ],
                  onChanged: (TodoStatus? next) {
                    setState(() => _statusFilter = next);
                    _loadTodos();
                  },
                ),
                DropdownButton<TodoPriority?>(
                  value: _priorityFilter,
                  hint: const Text('All priorities'),
                  items: <DropdownMenuItem<TodoPriority?>>[
                    const DropdownMenuItem<TodoPriority?>(
                      value: null,
                      child: Text('All priorities'),
                    ),
                    ...TodoPriority.values.map(
                      (TodoPriority p) => DropdownMenuItem<TodoPriority?>(
                        value: p,
                        child: Text(p.value),
                      ),
                    ),
                  ],
                  onChanged: (TodoPriority? next) {
                    setState(() => _priorityFilter = next);
                    _loadTodos();
                  },
                ),
              ],
            ),
            if (_notice != null) ...<Widget>[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _isError ? Colors.red.shade50 : Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _notice!,
                  style: TextStyle(
                    color: _isError
                        ? Colors.red.shade900
                        : Colors.green.shade900,
                  ),
                ),
              ),
            ],
            if (_selectedTodo != null) ...<Widget>[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Selected (${_selectedTodo!.id}): ${_selectedTodo!.title}\n'
                  'status=${_selectedTodo!.status.value} | '
                  'priority=${_selectedTodo!.priority.value}',
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (_todos.isEmpty)
              Text(
                _busy ? 'Loading todos...' : 'No todos loaded.',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else
              ..._todos.map(
                (Todo todo) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  child: ListTile(
                    title: Text(todo.title),
                    subtitle: Text(
                      '${todo.id} • ${todo.status.value} • ${todo.priority.value}'
                      '${todo.description != null ? '\n${todo.description}' : ''}',
                    ),
                    isThreeLine: todo.description != null,
                    trailing: Wrap(
                      spacing: 4,
                      children: <Widget>[
                        IconButton(
                          tooltip: 'Inspect (GET byId)',
                          icon: const Icon(Icons.info_outline),
                          onPressed: () => _inspectTodo(todo.id),
                        ),
                        IconButton(
                          tooltip: 'Next status',
                          icon: const Icon(Icons.sync),
                          onPressed: () => _cycleStatus(todo),
                        ),
                        IconButton(
                          tooltip: 'Delete',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _deleteTodo(todo.id),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

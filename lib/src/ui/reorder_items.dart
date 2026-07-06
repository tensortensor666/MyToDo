List<T> reorderItems<T>(List<T> items, int oldIndex, int newIndex) {
  final reordered = items.toList();
  final moved = reordered.removeAt(oldIndex);
  reordered.insert(newIndex, moved);
  return reordered;
}

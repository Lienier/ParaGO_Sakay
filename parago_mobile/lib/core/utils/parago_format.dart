class ParagoFormat {
  static String shortId(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return 'Unassigned';
    if (raw.length <= 8) return raw;
    return '${raw.substring(0, 4)}...${raw.substring(raw.length - 4)}';
  }

  static String statusLabel(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return 'Unknown';
    return raw
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map(
          (part) =>
              '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  static String dateTime(String? iso) {
    final time = _tryParse(iso);
    if (time == null) return 'Not available';
    final local = time.toLocal();
    final month = _monthName(local.month);
    final day = local.day.toString().padLeft(2, '0');
    final hour =
        local.hour == 0 ? 12 : (local.hour > 12 ? local.hour - 12 : local.hour);
    final minute = local.minute.toString().padLeft(2, '0');
    final suffix = local.hour >= 12 ? 'PM' : 'AM';
    return '$month $day, ${local.year} · $hour:$minute $suffix';
  }

  static String shortTime(String? iso) {
    final time = _tryParse(iso);
    if (time == null) return 'Now';
    final local = time.toLocal();
    final hour =
        local.hour == 0 ? 12 : (local.hour > 12 ? local.hour - 12 : local.hour);
    final minute = local.minute.toString().padLeft(2, '0');
    final suffix = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  static String relative(String? iso) {
    final time = _tryParse(iso);
    if (time == null) return 'Just now';
    final diff = DateTime.now().difference(time.toLocal());
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  static DateTime? _tryParse(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return DateTime.tryParse(value);
  }

  static String _monthName(int month) {
    const names = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return names[month - 1];
  }
}

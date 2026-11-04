const _months = [
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

/// "Nov 4, 2026 · 6:27 PM", or "Nov 4, 2026 · 6:27:14 PM" with [seconds].
String formatDateTime(DateTime dt, {bool seconds = false}) {
  final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final m = dt.minute.toString().padLeft(2, '0');
  final s = seconds ? ':${dt.second.toString().padLeft(2, '0')}' : '';
  final ampm = dt.hour >= 12 ? 'PM' : 'AM';
  return '${_months[dt.month - 1]} ${dt.day}, ${dt.year}  ·  $h:$m$s $ampm';
}

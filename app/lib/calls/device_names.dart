/// Похоже на виртуальное устройство (их не берём по умолчанию).
bool looksVirtual(String label) {
  final s = label.toLowerCase();
  const bad = [
    'virtual', 'виртуал', 'steam streaming', 'nvidia broadcast', 'voicemeeter', 'vb-audio',
    'cable output', 'cable input', 'obs', 'snap camera', 'xsplit', 'droidcam', 'manycam',
    'iriun', 'epoccam', 'nvidia rtx voice', 'krisp', 'camo',
  ];
  return bad.any(s.contains);
}

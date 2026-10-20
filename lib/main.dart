import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ───────── الألوان والأيقونات ─────────
const bg = Color(0xFF0D0E1A);
const surface = Color(0xFF191B2E);
const barColor = Color(0xFF23263F);
const palette = <Color>[
  Color(0xFFFF5D73),
  Color(0xFFFF9F43),
  Color(0xFFFFD166),
  Color(0xFF2EC4B6),
  Color(0xFF4CC9F0),
  Color(0xFF7B6CFF),
  Color(0xFFC77DFF),
  Color(0xFFFF7AC6),
];
const icons = <IconData>[
  Icons.music_note,
  Icons.sentiment_very_satisfied,
  Icons.celebration,
  Icons.notifications_active,
  Icons.pets,
  Icons.mic,
  Icons.bolt,
  Icons.favorite,
  Icons.rocket_launch,
  Icons.local_fire_department,
  Icons.theater_comedy,
  Icons.campaign,
  Icons.sports_esports,
  Icons.car_crash,
  Icons.thunderstorm,
  Icons.piano,
];
const speeds = <double>[0.5, 0.75, 1, 1.25, 1.5, 2];
const textScale = 1.1; // غيّر الرقم لتكبير أو تصغير الخط في التطبيق كله

bool _isAbs(String p) => p.contains('/') || p.contains('\\');

// ───────── الموديل ─────────
class SoundItem {
  String id, name, path, category;
  int color, icon, plays;
  bool fav;
  SoundItem({
    required this.id,
    required this.name,
    required this.path,
    this.category = '',
    this.color = 0,
    this.icon = 0,
    this.plays = 0,
    this.fav = false,
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'path': path,
    'category': category,
    'color': color,
    'icon': icon,
    'plays': plays,
    'fav': fav,
  };
  factory SoundItem.fromJson(Map<String, dynamic> j) => SoundItem(
    id: '${j['id']}',
    name: '${j['name']}',
    path: '${j['path']}',
    category: j['category'] ?? '',
    color: j['color'] ?? 0,
    icon: j['icon'] ?? 0,
    plays: j['plays'] ?? 0,
    fav: j['fav'] ?? false,
  );
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      fontFamily: "latefff",
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      colorScheme: const ColorScheme.dark(primary: Color(0xFF7B6CFF)),
    ),
    builder: (c, child) => MediaQuery(
      data: MediaQuery.of(c)
          .copyWith(textScaler: const TextScaler.linear(textScale)),
      child: Directionality(textDirection: TextDirection.rtl, child: child!),
    ),
    home: const Home(),
  );
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  AudioPlayer _player = AudioPlayer();
  final List<AudioPlayer> _extras = [];
  final List<StreamSubscription> _subs = [];
  List<SoundItem> _sounds = [];
  SoundItem? _current;
  bool _playing = false, _loop = false, _overlap = false, _loaded = false;
  double _volume = 1, _speed = 1;
  int _cols = 2, _sort = 0;
  String _query = '', _filter = 'all';
  Duration _pos = Duration.zero, _dur = Duration.zero;

  // التخزين
  String? _dir; // مجلد التطبيق الدائم
  Future<void> _saveChain = Future.value();

  String? get _dbPath => _dir == null ? null : '$_dir/soundboard.json';
  String? get _soundsDir => _dir == null ? null : '$_dir/sounds';
  String _full(SoundItem s) =>
      _isAbs(s.path) ? s.path : '$_soundsDir/${s.path}';

  @override
  void initState() {
    super.initState();
    _attach(_player);
    _load();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    for (final p in _extras) {
      p.dispose();
    }
    super.dispose();
  }

  void _attach(AudioPlayer p) {
    for (final s in _subs) {
      s.cancel();
    }
    _subs
      ..clear()
      ..addAll([
        p.onPositionChanged.listen((v) {
          if (mounted) setState(() => _pos = v);
        }),
        p.onDurationChanged.listen((v) {
          if (mounted) setState(() => _dur = v);
        }),
        p.onPlayerStateChanged.listen((s) {
          if (mounted) setState(() => _playing = s == PlayerState.playing);
        }),
        p.onPlayerComplete.listen((_) {
          if (mounted) setState(() => _pos = Duration.zero);
        }),
      ]);
  }

  // ───────── التخزين: ملف JSON + نسخة احتياطية + SharedPreferences ─────────
  Map<String, dynamic>? _parse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final m = jsonDecode(raw);
      return m is Map<String, dynamic> ? m : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {}
    try {
      final d = await getApplicationSupportDirectory();
      await Directory('${d.path}/sounds').create(recursive: true);
      _dir = d.path;
    } catch (_) {}

    // نجرّب بالترتيب: الملف الأساسي، النسخة الاحتياطية، SharedPreferences
    Map<String, dynamic>? db;
    final path = _dbPath;
    if (path != null) {
      for (final p in [path, '$path.bak']) {
        try {
          final f = File(p);
          if (await f.exists()) db ??= _parse(await f.readAsString());
        } catch (_) {}
      }
    }
    db ??= _parse(prefs?.getString('db'));

    var list = <SoundItem>[];
    final s = (db?['settings'] as Map?) ?? {};
    if (db != null) {
      for (final e in (db['sounds'] as List? ?? [])) {
        try {
          list.add(SoundItem.fromJson(Map<String, dynamic>.from(e)));
        } catch (_) {}
      }
    } else {
      // دعم نسخة التخزين القديمة
      for (final e in (prefs?.getStringList('sounds') ?? [])) {
        try {
          list.add(SoundItem.fromJson(jsonDecode(e)));
        } catch (_) {}
      }
    }
    if (!mounted) return;
    setState(() {
      _sounds = list;
      _volume = ((s['volume'] ?? 1) as num).toDouble().clamp(0.0, 1.0);
      _speed = ((s['speed'] ?? 1) as num).toDouble();
      if (!speeds.contains(_speed)) _speed = 1;
      _loop = s['loop'] ?? false;
      _overlap = s['overlap'] ?? false;
      _cols = ((s['cols'] ?? 2) as num).toInt().clamp(1, 3);
      _sort = ((s['sort'] ?? 0) as num).toInt().clamp(0, 2);
      _loaded = true;
    });
    if (db == null && list.isNotEmpty) _save(); // ترحيل البيانات القديمة
  }

  void _save() {
    if (!_loaded) return; // ما نحفظش قبل ما التحميل يخلص
    final raw = jsonEncode({
      'v': 2,
      'settings': {
        'volume': _volume,
        'speed': _speed,
        'loop': _loop,
        'overlap': _overlap,
        'cols': _cols,
        'sort': _sort,
      },
      'sounds': _sounds.map((e) => e.toJson()).toList(),
    });
    // الحفظ بيتنفذ بالدور عشان ما يحصلش تداخل
    _saveChain = _saveChain.then((_) => _write(raw));
  }

  Future<void> _write(String raw) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('db', raw);
    } catch (_) {}
    final path = _dbPath;
    if (path == null) return;
    try {
      final tmp = File('$path.tmp');
      await tmp.writeAsString(raw, flush: true);
      final main = File(path);
      if (await main.exists()) await main.copy('$path.bak');
      await tmp.rename(path);
    } catch (_) {}
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  // ───────── التشغيل ─────────
  Future<void> _play(SoundItem item) async {
    HapticFeedback.lightImpact();
    if (!File(_full(item)).existsSync()) {
      _toast('ملف الصوت مش موجود، عدّل الزر واختار الملف تاني');
      return;
    }
    try {
      if (_overlap && _current != null && _playing) {
        final old = _player;
        _extras.add(old);
        old.onPlayerComplete.first
            .then((_) {
              _extras.remove(old);
              old.dispose();
            })
            .catchError((_) {});
        _player = AudioPlayer();
        _attach(_player);
      } else {
        await _player.stop();
      }
      item.plays++;
      setState(() => _current = item);
      _save();
      await _player.setReleaseMode(_loop ? ReleaseMode.loop : ReleaseMode.stop);
      await _player.setPlaybackRate(_speed);
      await _player.play(DeviceFileSource(_full(item)), volume: _volume);
    } catch (_) {
      _toast('حصلت مشكلة في تشغيل الصوت');
    }
  }

  Future<void> _stopAll() async {
    for (final p in _extras) {
      try {
        await p.stop();
        await p.dispose();
      } catch (_) {}
    }
    _extras.clear();
    await _player.stop();
    if (!mounted) return;
    setState(() {
      _current = null;
      _pos = Duration.zero;
    });
  }

  Future<void> _togglePause() async {
    if (_playing) {
      await _player.pause();
    } else if (_current != null) {
      _pos == Duration.zero ? await _play(_current!) : await _player.resume();
    }
  }

  void _playRandom(List<SoundItem> list) {
    if (list.isEmpty) return;
    _play(list[Random().nextInt(list.length)]);
  }

  // ───────── إضافة / تعديل / حذف ─────────
  Future<void> _openEditor([SoundItem? existing]) async {
    final result = await showModalBottomSheet<SoundItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) =>
          Editor(existing: existing, categories: _cats, soundsDir: _soundsDir),
    );
    if (result == null) return;
    if (existing != null && existing.path != result.path) {
      _deleteOwnedFile(existing); // نمسح الملف القديم لو اتغير
    }
    setState(() {
      if (existing == null) {
        _sounds.add(result);
      } else {
        existing
          ..name = result.name
          ..path = result.path
          ..category = result.category
          ..color = result.color
          ..icon = result.icon;
      }
    });
    _save();
  }

  void _deleteOwnedFile(SoundItem item) {
    if (_isAbs(item.path) || _soundsDir == null) return; // مش ملفنا
    try {
      File(_full(item)).delete();
    } catch (_) {}
  }

  Future<void> _confirmDelete(SoundItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: surface,
        title: const Text('حذف الزر؟'),
        content: Text('هتتمسح "${item.name}" نهائياً.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: palette[0]),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('احذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (_current?.id == item.id) await _stopAll();
    _deleteOwnedFile(item);
    setState(() => _sounds.removeWhere((e) => e.id == item.id));
    _save();
  }

  void _options(SoundItem item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(item.fav ? Icons.star_border : Icons.star),
              title: Text(item.fav ? 'شيل من المفضلة' : 'أضف للمفضلة'),
              onTap: () {
                Navigator.pop(context);
                setState(() => item.fav = !item.fav);
                _save();
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('تعديل الاسم واللون والأيقونة والتصنيف'),
              onTap: () {
                Navigator.pop(context);
                _openEditor(item);
              },
            ),
            ListTile(
              leading: const Icon(Icons.restart_alt),
              title: Text('تصفير عدد التشغيل (${item.plays})'),
              onTap: () {
                Navigator.pop(context);
                setState(() => item.plays = 0);
                _save();
              },
            ),
            ListTile(
              leading: Icon(Icons.delete, color: palette[0]),
              title: Text('حذف', style: TextStyle(color: palette[0])),
              onTap: () {
                Navigator.pop(context);
                _confirmDelete(item);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ───────── الفلترة والترتيب ─────────
  List<String> get _cats => _sounds
      .map((e) => e.category)
      .where((e) => e.isNotEmpty)
      .toSet()
      .toList();

  List<SoundItem> get _visible {
    final l = _sounds.where((e) => e.name.contains(_query)).where((e) {
      if (_filter == 'all') return true;
      if (_filter == 'fav') return e.fav;
      return e.category == _filter;
    }).toList();
    if (_sort == 1) l.sort((a, b) => a.name.compareTo(b.name));
    if (_sort == 2) l.sort((a, b) => b.plays.compareTo(a.plays));
    return [...l.where((e) => e.fav), ...l.where((e) => !e.fav)];
  }

  // ───────── الواجهة ─────────
  @override
  Widget build(BuildContext context) {
    if (_filter != 'all' && _filter != 'fav' && !_cats.contains(_filter)) {
      _filter = 'all';
    }
    final items = _visible;
    final totalPlays = _sounds.fold<int>(0, (a, e) => a + e.plays);
    final bottomSpace = _current != null ? 200.0 : 100.0;
    return Scaffold(
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: _current != null ? 160 : 0),
        child: FloatingActionButton.extended(
          onPressed: () => _openEditor(),
          icon: const Icon(Icons.add),
          label: const Text('صوت جديد'),
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'لوحة الأصوات',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              Text(
                                '${_sounds.length} صوت  •  $totalPlays تشغيل',
                                style: const TextStyle(color: Colors.white54),
                              ),
                            ],
                          ),
                        ),
                        IconButton.filled(
                          style: IconButton.styleFrom(
                            backgroundColor: palette[0],
                          ),
                          onPressed: (_current == null && _extras.isEmpty)
                              ? null
                              : _stopAll,
                          icon: const Icon(Icons.stop_rounded),
                          tooltip: 'إيقاف الكل',
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    child: TextField(
                      onChanged: (v) => setState(() => _query = v),
                      decoration: InputDecoration(
                        hintText: 'دوّر على صوت...',
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 48,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      children: [
                        _chip('الكل', 'all'),
                        _chip('⭐ المفضلة', 'fav'),
                        for (final c in _cats) _chip(c, c),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'صوت عشوائي',
                          onPressed: () => _playRandom(items),
                          icon: const Icon(Icons.shuffle),
                        ),
                        IconButton(
                          tooltip: 'تغيير شكل العرض',
                          onPressed: () {
                            setState(() => _cols = _cols % 3 + 1);
                            _save();
                          },
                          icon: Icon(
                            _cols == 1
                                ? Icons.view_agenda
                                : _cols == 2
                                ? Icons.grid_view
                                : Icons.apps,
                          ),
                        ),
                        PopupMenuButton<int>(
                          tooltip: 'ترتيب',
                          icon: const Icon(Icons.sort),
                          color: surface,
                          onSelected: (v) {
                            setState(() => _sort = v);
                            _save();
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 0, child: Text('حسب الإضافة')),
                            PopupMenuItem(value: 1, child: Text('بالاسم')),
                            PopupMenuItem(
                              value: 2,
                              child: Text('الأكثر تشغيلاً'),
                            ),
                          ],
                        ),
                        const Spacer(),
                        FilterChip(
                          avatar: const Icon(Icons.layers, size: 18),
                          label: const Text('تشغيل مع بعض'),
                          selected: _overlap,
                          onSelected: (v) {
                            setState(() => _overlap = v);
                            _save();
                          },
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ),
                ),
                if (!_loaded)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (items.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text(
                        _sounds.isEmpty
                            ? 'اضغط "صوت جديد" وضيف أول زر'
                            : 'مفيش نتيجة',
                        style: const TextStyle(color: Colors.white54),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(20, 8, 20, bottomSpace),
                    sliver: SliverGrid.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: _cols,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                        childAspectRatio: _cols == 1
                            ? 3.4
                            : (_cols == 2 ? 0.95 : 0.8),
                      ),
                      itemCount: items.length,
                      itemBuilder: (_, i) => _pad(items[i]),
                    ),
                  ),
              ],
            ),
            Positioned(left: 12, right: 12, bottom: 12, child: _playerBar()),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, String value) => Padding(
    padding: const EdgeInsetsDirectional.only(end: 8),
    child: ChoiceChip(
      label: Text(label),
      selected: _filter == value,
      onSelected: (_) => setState(() => _filter = value),
    ),
  );

  Widget _pad(SoundItem s) {
    final c = palette[s.color % palette.length];
    final active = _current?.id == s.id && _playing;
    final icon = active ? Icons.graphic_eq : icons[s.icon % icons.length];
    final name = Text(
      s.name,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: _cols == 3 ? 14 : 18,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
    );
    final meta = Text(
      [if (s.category.isNotEmpty) s.category, '${s.plays}×'].join('  •  '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 11, color: Colors.white70),
    );
    return GestureDetector(
      onTap: () => _play(s),
      onLongPress: () {
        HapticFeedback.mediumImpact();
        _options(s);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [c, Color.lerp(c, Colors.black, 0.45)!],
          ),
          boxShadow: active
              ? [BoxShadow(color: c.withOpacity(.6), blurRadius: 24)]
              : [],
          border: Border.all(
            color: active ? Colors.white : Colors.transparent,
            width: 2,
          ),
        ),
        child: _cols == 1
            ? Row(
                children: [
                  Icon(icon, size: 34, color: Colors.white),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [name, meta],
                    ),
                  ),
                  if (s.fav) const Icon(Icons.star, color: Colors.white),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Icon(
                        icon,
                        size: _cols == 3 ? 26 : 34,
                        color: Colors.white,
                      ),
                      if (s.fav)
                        const Icon(Icons.star, color: Colors.white, size: 20),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [name, if (_cols == 2) meta],
                  ),
                ],
              ),
      ),
    );
  }

  String _fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  Widget _playerBar() {
    final s = _current;
    if (s == null) return const SizedBox.shrink();
    final maxMs = (_dur.inMilliseconds == 0 ? 1 : _dur.inMilliseconds);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
      decoration: BoxDecoration(
        color: barColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 20)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: palette[s.color % palette.length],
                child: Icon(icons[s.icon % icons.length], color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  s.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'تكرار',
                onPressed: () async {
                  setState(() => _loop = !_loop);
                  await _player.setReleaseMode(
                    _loop ? ReleaseMode.loop : ReleaseMode.stop,
                  );
                  _save();
                },
                icon: Icon(
                  Icons.repeat,
                  color: _loop ? palette[3] : Colors.white54,
                ),
              ),
              IconButton.filled(
                onPressed: _togglePause,
                icon: Icon(
                  _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                ),
              ),
              IconButton(
                onPressed: _stopAll,
                icon: const Icon(Icons.stop_rounded),
              ),
            ],
          ),
          Row(
            children: [
              Text(
                _fmt(_pos),
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
              Expanded(
                child: Slider(
                  value: _pos.inMilliseconds.clamp(0, maxMs).toDouble(),
                  max: maxMs.toDouble(),
                  onChanged: (v) =>
                      _player.seek(Duration(milliseconds: v.toInt())),
                ),
              ),
              Text(
                _fmt(_dur),
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ],
          ),
          Row(
            children: [
              const Icon(Icons.volume_up, size: 18, color: Colors.white54),
              Expanded(
                child: Slider(
                  value: _volume,
                  onChanged: (v) {
                    setState(() => _volume = v);
                    _player.setVolume(v);
                  },
                  onChangeEnd: (_) => _save(),
                ),
              ),
              TextButton(
                onPressed: () async {
                  final i = speeds.indexOf(_speed);
                  setState(() => _speed = speeds[(i + 1) % speeds.length]);
                  await _player.setPlaybackRate(_speed);
                  _save();
                },
                child: Text('${_speed}x'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ───────── نافذة الإضافة / التعديل ─────────
class Editor extends StatefulWidget {
  final SoundItem? existing;
  final List<String> categories;
  final String? soundsDir;
  const Editor({
    super.key,
    this.existing,
    this.categories = const [],
    this.soundsDir,
  });
  @override
  State<Editor> createState() => _EditorState();
}

class _EditorState extends State<Editor> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _cat = TextEditingController(
    text: widget.existing?.category ?? '',
  );
  late int _color = widget.existing?.color ?? 0;
  late int _icon = widget.existing?.icon ?? 0;
  String? _srcPath, _fileName, _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _cat.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final f = await FilePicker.pickFile(type: FileType.audio);
    if (f?.path == null) return;
    setState(() {
      _srcPath = f!.path;
      _fileName = f.name;
      _error = null;
      if (_name.text.isEmpty) {
        _name.text = _fileName!.replaceAll(RegExp(r'\.[^.]+$'), '');
      }
    });
  }

  Future<void> _submit() async {
    if (_busy) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'اكتب اسم للزر');
      return;
    }
    setState(() => _busy = true);
    final id =
        widget.existing?.id ?? DateTime.now().millisecondsSinceEpoch.toString();
    var path = widget.existing?.path ?? '';
    if (_srcPath != null) {
      var saved = false;
      if (widget.soundsDir != null) {
        try {
          // ننسخ الملف جوه التطبيق ونخزن اسمه بس (مسار نسبي)
          final safe = _fileName!.replaceAll(RegExp(r'[^\w\.\-]'), '_');
          final rel = '${id}_${DateTime.now().millisecondsSinceEpoch}_$safe';
          await File(_srcPath!).copy('${widget.soundsDir}/$rel');
          path = rel;
          saved = true;
        } catch (_) {}
      }
      if (!saved) path = _srcPath!; // لو النسخ فشل نستخدم المسار الأصلي
    }
    if (path.isEmpty) {
      setState(() {
        _error = 'اختار ملف صوت';
        _busy = false;
      });
      return;
    }
    if (!mounted) return;
    Navigator.pop(
      context,
      SoundItem(
        id: id,
        name: name,
        path: path,
        category: _cat.text.trim(),
        color: _color,
        icon: _icon,
      ),
    );
  }

  InputDecoration _dec(String label) => InputDecoration(
    labelText: label,
    filled: true,
    fillColor: bg,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide.none,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              editing ? 'تعديل الزر' : 'صوت جديد',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            TextField(controller: _name, decoration: _dec('اسم الزر')),
            const SizedBox(height: 12),
            TextField(controller: _cat, decoration: _dec('التصنيف (اختياري)')),
            if (widget.categories.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final c in widget.categories)
                    ActionChip(label: Text(c), onPressed: () => _cat.text = c),
                ],
              ),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pick,
              icon: Icon(_fileName == null ? Icons.audio_file : Icons.check),
              label: Text(
                _fileName ?? (editing ? 'تغيير ملف الصوت' : 'اختار ملف صوت'),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: TextStyle(color: palette[0])),
              ),
            const SizedBox(height: 16),
            const Text('اللون', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (var i = 0; i < palette.length; i++)
                  GestureDetector(
                    onTap: () => setState(() => _color = i),
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: palette[i],
                      child: _color == i
                          ? const Icon(Icons.check, color: Colors.white)
                          : null,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('الأيقونة', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (var i = 0; i < icons.length; i++)
                  GestureDetector(
                    onTap: () => setState(() => _icon = i),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _icon == i ? palette[_color] : bg,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(icons[i], color: Colors.white),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : _submit,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_busy ? 'جاري الحفظ...' : 'حفظ'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

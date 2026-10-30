import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'http/http.dart' as http;
import 'dart:convert';

void main() {
  runApp(const GeoGuideApp());
}

class GeoGuideApp extends StatelessWidget {
  const GeoGuideApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    const Color primaryGreen = Color(0xFF1B5E20);
    
    return MaterialApp(
      title: 'AI Helyi Idegenvezető',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        primaryColor: primaryGreen,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryGreen,
          primary: primaryGreen,
          secondary: const Color(0xFF388E3C),
        ),
        scaffoldBackgroundColor: const Color(0xFFF4F6F4),
        appBarTheme: const AppBarTheme(
          backgroundColor: primaryGreen,
          foregroundColor: Colors.white,
          centerTitle: true,
          elevation: 2,
        ),
        cardTheme: CardTheme(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryGreen,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ),
      home: const GuideHomePage(),
    );
  }
}

class GuideItem {
  final String id;
  final String title;
  final String description;
  final String category;
  bool isSelectedForTrip;

  GuideItem({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    this.isSelectedForTrip = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'category': category,
    'isSelectedForTrip': isSelectedForTrip,
  };

  factory GuideItem.fromJson(Map<String, dynamic> json) => GuideItem(
    id: json['id'],
    title: json['title'],
    description: json['description'],
    category: json['category'],
    isSelectedForTrip: json['isSelectedForTrip'] ?? false,
  );
}

class GuideHomePage extends StatefulWidget {
  const GuideHomePage({Key? key}) : super(key: key);

  @override
  _GuideHomePageState createState() => _GuideHomePageState();
}

class _GuideHomePageState extends State<GuideHomePage> with SingleTickerProviderStateMixin {
  final FlutterTts _flutterTts = FlutterTts();
  late TabController _tabController;
  
  // ITT ADHATOD MEG A GEMINI API KULCSODAT
  final String _geminiApiKey = "YOUR_GEMINI_API_KEY_HERE";

  double _selectedRadius = 10.0;
  String _selectedCategory = 'Történelem';
  bool _isLoading = false;
  bool _isPlaying = false;
  String _currentStatus = 'Készen áll. Válaszd ki az üzemmódot!';
  String _currentSpeakingText = '';

  final TextEditingController _locationController = TextEditingController();
  List<GuideItem> _plannedItems = [];

  final List<String> _categories = [
    'Napi aktuális (Események)',
    'Történelem',
    'Természeti látnivaló',
    'Híres ember',
    'Földrajz',
    'Mondák és legendák'
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initTts();
    _loadSavedPlaylist();
  }

  void _initTts() async {
    await _flutterTts.setLanguage("hu-HU");
    await _flutterTts.setSpeechRate(0.48); // Kellemes beszédtempó
    await _flutterTts.setPitch(1.0);

    _flutterTts.setStartHandler(() => setState(() => _isPlaying = true));
    _flutterTts.setCompletionHandler(() => setState(() => _isPlaying = false));
    _flutterTts.setErrorHandler((msg) => setState(() {
      _isPlaying = false;
      _currentStatus = "TTS hiba: $msg";
    }));
  }

  Future<void> _loadSavedPlaylist() async {
    final prefs = await SharedPreferences.getInstance();
    List<String>? savedJson = prefs.getStringList('trip_playlist');
    if (savedJson != null) {
      setState(() {
        _plannedItems = savedJson.map((item) => GuideItem.fromJson(jsonDecode(item))).toList();
      });
    }
  }

  Future<void> _savePlaylist() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> jsonList = _plannedItems.map((item) => jsonEncode(item.toJson())).toList();
    await prefs.setStringList('trip_playlist', jsonList);
  }

  // --- 10 NAPOS ISMTÉTLŐDÉS KISZŰRÉSE ---
  Future<bool> _isAlreadyPlayed(String topicId) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> history = prefs.getStringList('played_topics') ?? [];
    int now = DateTime.now().millisecondsSinceEpoch;
    int tenDaysInMillis = 10 * 24 * 60 * 60 * 1000;

    List<String> updatedHistory = [];
    bool found = false;

    for (var item in history) {
      var parts = item.split('|');
      if (parts.length == 2) {
        String id = parts[0];
        int timestamp = int.tryParse(parts[1]) ?? 0;

        if (now - timestamp < tenDaysInMillis) {
          updatedHistory.add(item);
          if (id == topicId) found = true;
        }
      }
    }
    await prefs.setStringList('played_topics', updatedHistory);
    return found;
  }

  Future<void> _markAsPlayed(String topicId) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> history = prefs.getStringList('played_topics') ?? [];
    int now = DateTime.now().millisecondsSinceEpoch;
    history.add('$topicId|$now');
    await prefs.setStringList('played_topics', history);
  }

  // --- GEMINI API LEKÉRDEZÉS ---
  Future<String> _fetchGeminiGuideText(String prompt) async {
    if (_geminiApiKey == "YOUR_GEMINI_API_KEY_HERE" || _geminiApiKey.isEmpty) {
      // Ha nincs beállítva API kulcs, egy szemléltető szöveget ad vissza a teszteléshez
      return "Ez egy teszt leírás. A pontos adatokért illeszd be a Gemini API kulcsodat a kódba! "
             "Képzeld el, hogy a kiválasztott területről hallasz izgalmas helytörténeti és természeti részleteket.";
    }

    final url = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$_geminiApiKey');
    
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "contents": [{
            "parts": [{"text": prompt}]
          }]
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['candidates'][0]['content']['parts'][0]['text'] ?? "Nem található információ.";
      } else {
        return "Sajnálom, hiba történt a hálózati lekérdezés során. Kód: ${response.statusCode}";
      }
    } catch (e) {
      return "Hálózati hiba: $e";
    }
  }

  // --- GPS POZÍCIÓ LEKÉRÉSE ---
  Future<Position?> _determinePosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _currentStatus = 'A GPS ki van kapcsolva a telefonon.');
      return null;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() => _currentStatus = 'A GPS engedély megadása szükséges.');
        return null;
      }
    }
    return await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
  }

  // --- ÉLŐ GPS ALAPÚ KERESÉS ---
  Future<void> _exploreLiveSurroundings() async {
    await _stopSpeaking();
    setState(() {
      _isLoading = true;
      _currentStatus = 'GPS pozíció lekérése...';
    });

    Position? pos = await _determinePosition();
    if (pos == null) {
      setState(() => _isLoading = false);
      return;
    }

    String topicId = "geo_${pos.latitude.toStringAsFixed(2)}_${pos.longitude.toStringAsFixed(2)}_$_selectedCategory";
    bool heardRecently = await _isAlreadyPlayed(topicId);

    if (heardRecently) {
      setState(() {
        _isLoading = false;
        _currentStatus = 'Ezen a környéken az elmúlt 10 napban már hallottál információt!';
      });
      await _speakText("Ezen a környéken az elmúlt tíz napban már hallottál információt. Haladj tovább egy újabb területre!");
      return;
    }

    setState(() => _currentStatus = 'AI idegenvezetői tartalom generálása (${_selectedRadius.toInt()} km)...');

    String prompt = "Te egy profi, barátságos felolvasó idegenvezető vagy. A felhasználó jelenleg a következő GPS koordinátákon tartózkodik: Szélesség ${pos.latitude}, Hosszúság ${pos.longitude}. "
        "Írj egy kb. 1.5-2 perces, hangoskönyv-stílusú összefoglalót a(z) '${_selectedCategory}' kategóriában, a helyszín ${_selectedRadius.toInt()} km-es körzetéről. "
        "Ne használj címsorokat vagy speciális írásjeleket, közvetlenül felolvasható, folyamatos magyar szöveget fogalmazz meg!";

    String resultText = await _fetchGeminiGuideText(prompt);
    await _markAsPlayed(topicId);

    setState(() {
      _isLoading = false;
      _currentSpeakingText = resultText;
      _currentStatus = 'Felolvasás folyamatban...';
    });

    await _speakText(resultText);
  }

  // --- OTTHONI ÚTITERV KERESÉS ---
  Future<void> _searchAndPlan(String targetLocation) async {
    if (targetLocation.trim().isEmpty) return;
    await _stopSpeaking();

    setState(() {
      _isLoading = true;
      _currentStatus = 'Keresés és útiterv generálása: $targetLocation...';
    });

    String prompt = "A felhasználó a következő településre/területre tervez utazni: '$targetLocation'. "
        "Gyűjts össze 2 érdekes, konkrét látnivalót vagy történetet a(z) '${_selectedCategory}' kategóriában a helyszín ${_selectedRadius.toInt()} km-es körzetéből. "
        "Válaszolj kizárólag egy JSON tömbként a következő formátumban, más szöveget ne írj: "
        "[{\"title\": \"Cím\", \"description\": \"Kimerítő, 1 perces felolvasható leírás\"}]";

    String jsonResponse = await _fetchGeminiGuideText(prompt);

    try {
      // Megpróbáljuk kinyerni a JSON-t a válaszból
      int startIndex = jsonResponse.indexOf('[');
      int endIndex = jsonResponse.lastIndexOf(']') + 1;
      
      if (startIndex != -1 && endIndex != -1) {
        String cleanJson = jsonResponse.substring(startIndex, endIndex);
        List<dynamic> parsed = jsonDecode(cleanJson);

        List<GuideItem> newItems = parsed.map((e) => GuideItem(
          id: '${targetLocation}_${DateTime.now().millisecondsSinceEpoch}_${e['title']}',
          title: e['title'] ?? targetLocation,
          description: e['description'] ?? '',
          category: _selectedCategory,
        )).toList();

        setState(() {
          _plannedItems.addAll(newItems);
          _currentStatus = 'Sikeresen hozzáadva az útitervhez! Pipáld ki, amit szeretnél.';
        });
        _savePlaylist();
      } else {
        // Ha nem sikerült JSON-ként értelmezni, sima elemként mentjük
        _addSinglePlannedItem(targetLocation, jsonResponse);
      }
    } catch (e) {
      _addSinglePlannedItem(targetLocation, jsonResponse);
    }

    setState(() => _isLoading = false);
  }

  void _addSinglePlannedItem(String location, String text) {
    GuideItem item = GuideItem(
      id: '${location}_${DateTime.now().millisecondsSinceEpoch}',
      title: '$location - $_selectedCategory',
      description: text,
      category: _selectedCategory,
    );
    setState(() {
      _plannedItems.add(item);
      _currentStatus = 'Tartalom elmentve az útitervbe!';
    });
    _savePlaylist();
  }

  Future<void> _speakText(String text) async {
    await _flutterTts.stop();
    setState(() => _currentSpeakingText = text);
    await _flutterTts.speak(text);
  }

  Future<void> _stopSpeaking() async {
    await _flutterTts.stop();
    setState(() => _isPlaying = false);
  }

  @override
  void dispose() {
    _flutterTts.stop();
    _tabController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Helyi Idegenvezető'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.my_location), text: 'Élő GPS Séta'),
            Tab(icon: Icon(Icons.map_outlined), text: 'Otthoni Tervező'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Státusz sáv és Lejátszás vezérlő
          Container(
            color: Colors.green.shade50,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _currentStatus,
                    style: TextStyle(color: Colors.green.shade900, fontWeight: FontWeight.w500, fontSize: 13),
                  ),
                ),
                if (_isPlaying)
                  IconButton(
                    icon: const Icon(Icons.stop_circle, color: Colors.red, size: 32),
                    onPressed: _stopSpeaking,
                    tooltip: 'Felolvasás leállítása',
                  ),
              ],
            ),
          ),

          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // 1. ÉLŐ GPS LAP
                _buildLiveGpsTab(),
                // 2. OTTHONI TERVEZŐ LAP
                _buildPlannerTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- ÉLŐ GPS NÉZET ---
  Widget _buildLiveGpsTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Keresési sugár: ${_selectedRadius.toInt()} km', style: const TextStyle(fontWeight: FontWeight.bold)),
                  Slider(
                    value: _selectedRadius,
                    min: 5,
                    max: 50,
                    divisions: 3,
                    label: '${_selectedRadius.toInt()} km',
                    onChanged: (val) => setState(() => _selectedRadius = val),
                  ),
                  const SizedBox(height: 10),
                  const Text('Válassz tématakört:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 5),
                  DropdownButtonFormField<String>(
                    value: _selectedCategory,
                    decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10)),
                    items: _categories.map((cat) => DropdownMenuItem(value: cat, child: Text(cat))).toList(),
                    onChanged: (val) => setState(() => _selectedCategory = val!),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : ElevatedButton.icon(
                  icon: const Icon(Icons.play_arrow_rounded, size: 28),
                  label: const Text('Környék felfedezése & Mesélés', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  onPressed: _exploreLiveSurroundings,
                ),
          const SizedBox(height: 16),
          if (_currentSpeakingText.isNotEmpty) ...[
            const Text("Jelenleg felolvasott szöveg:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 5),
            Expanded(
              child: SingleChildScrollView(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
                  child: Text(_currentSpeakingText, style: const TextStyle(fontSize: 14, height: 1.4)),
                ),
              ),
            ),
          ] else
            const Spacer(),
        ],
      ),
    );
  }

  // --- OTTHONI TERVEZŐ NÉZET ---
  Widget _buildPlannerTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _locationController,
                  decoration: const InputDecoration(
                    hintText: 'Pl. Visegrád, Szarvas...',
                    labelText: 'Célállomás / Település',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _isLoading ? null : () => _searchAndPlan(_locationController.text),
                child: const Text('Keresés'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedCategory,
                  decoration: const InputDecoration(labelText: 'Kategória', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 8)),
                  items: _categories.map((cat) => DropdownMenuItem(value: cat, child: Text(cat, style: const TextStyle(fontSize: 12)))).toList(),
                  onChanged: (val) => setState(() => _selectedCategory = val!),
                ),
              ),
              const SizedBox(width: 8),
              Text('${_selectedRadius.toInt()} km', style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Mentett Útiterv (Pipával jelölve):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              if (_plannedItems.isNotEmpty)
                TextButton(
                  onPressed: () {
                    setState(() => _plannedItems.clear());
                    _savePlaylist();
                  },
                  child: const Text('Lista törlése', style: TextStyle(color: Colors.red, fontSize: 12)),
                ),
            ],
          ),
          Expanded(
            child: _plannedItems.isEmpty
                ? const Center(child: Text('Még nincs elmentett elemed.\nKeress rá egy településre fent!', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    itemCount: _plannedItems.length,
                    itemBuilder: (context, index) {
                      final item = _plannedItems[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          leading: Checkbox(
                            value: item.isSelectedForTrip,
                            onChanged: (bool? val) {
                              setState(() => item.isSelectedForTrip = val ?? false);
                              _savePlaylist();
                            },
                          ),
                          title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          subtitle: Text(item.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                          trailing: IconButton(
                            icon: const Icon(Icons.volume_up, color: Colors.green),
                            onPressed: () => _speakText(item.description),
                            tooltip: 'Előhallgatás',
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

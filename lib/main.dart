import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ai_barcode_scanner/ai_barcode_scanner.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'マイ蔵書管理',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const BookScanPage(),
    );
  }
}

class BookScanPage extends StatefulWidget {
  const BookScanPage({super.key});

  @override
  State<BookScanPage> createState() => _BookScanPageState();
}

class BulkBookData {
  final String isbn;
  final String title;
  final String author;
  final TextEditingController volumeController;

  BulkBookData({
    required this.isbn,
    required this.title,
    required this.author,
    required String initialVolume,
  }) : volumeController = TextEditingController(text: initialVolume);

  void dispose() {
    volumeController.dispose();
  }
}

class _BookScanPageState extends State<BookScanPage> with SingleTickerProviderStateMixin {
  String _scannedIsbn = 'まだ入力されていません';
  String _bookTitle = '';
  String _bookAuthors = '';
  bool _isLoading = false;

  bool _isAlreadyOwned = false;
  String _ownedShelfName = '';

  String _detectedVolume = '';

  List<Map<String, dynamic>> _bookshelves = [
    {'name': '全般', 'books': <Map<String, dynamic>>[]}
  ];
  
  int _selectedShelfIndex = 0;
  late TabController _tabController;

  final TextEditingController _isbnController = TextEditingController();
  final TextEditingController _newShelfController = TextEditingController();
  final TextEditingController _seriesNameEditController = TextEditingController();
  final TextEditingController _volumeEditController = TextEditingController();
  
  final TextEditingController _bulkIsbnController = TextEditingController();
  List<BulkBookData> _bulkResultList = [];
  bool _isBulkLoading = false;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  final TextEditingController _editTitleController = TextEditingController();
  final TextEditingController _editAuthorController = TextEditingController();

  final TextEditingController _backupDataController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadBookshelves();
    _tabController = TabController(length: 2, vsync: this);
    
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _isbnController.dispose();
    _newShelfController.dispose();
    _seriesNameEditController.dispose();
    _volumeEditController.dispose();
    _bulkIsbnController.dispose();
    _searchController.dispose();
    _editTitleController.dispose();
    _editAuthorController.dispose();
    _backupDataController.dispose();
    _tabController.dispose();
    for (var item in _bulkResultList) {
      item.dispose();
    }
    super.dispose();
  }

  Future<void> _loadBookshelves() async {
    final prefs = await SharedPreferences.getInstance();
    final String? bookshelvesString = prefs.getString('bookshelves_data_v2');
    if (bookshelvesString != null) {
      final List<dynamic> decodedData = json.decode(bookshelvesString);
      setState(() {
        _bookshelves = decodedData.map((shelf) {
          final List<dynamic> booksList = shelf['books'] ?? [];
          return {
            'name': shelf['name'] as String,
            'books': booksList.map((b) => Map<String, dynamic>.from(b)).toList(),
          };
        }).toList();
      });
    }
  }

  Future<void> _saveBookshelvesToDevice() async {
    final prefs = await SharedPreferences.getInstance();
    final String encodedData = json.encode(_bookshelves);
    await prefs.setString('bookshelves_data_v2', encodedData);
  }

  void _showBackupRestoreDialog() {
    final String jsonString = json.encode(_bookshelves);
    _backupDataController.text = jsonString;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: const [
              Icon(Icons.settings_backup_restore, color: Colors.blueGrey),
              SizedBox(width: 5),
              Text('データバックアップ・復元', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('📤 データの書き出し (保存する)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blue)),
                const SizedBox(height: 5),
                const Text('以下の文字列をすべてコピーして、メモ帳やメール等に保存してください。', style: TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 5),
                TextField(
                  controller: _backupDataController,
                  readOnly: true,
                  maxLines: 4,
                  decoration: const InputDecoration(border: OutlineInputBorder(), fillColor: Colors.grey),
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                ),
                const SizedBox(height: 5),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: jsonString));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('バックアップデータをクリップボードにコピーしました！')),
                      );
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('データをコピーする'),
                  ),
                ),
                const Divider(height: 30),
                const Text('📥 データの読み込み (復元する)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.red)),
                const SizedBox(height: 5),
                const Text('注意: 復元すると、現在アプリ内にある本棚はすべて上書き消去されます。', style: TextStyle(fontSize: 11, color: Colors.red)),
                const SizedBox(height: 5),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _showRestorePasteDialog();
                    },
                    icon: const Icon(Icons.paste, color: Colors.white),
                    label: const Text('バックアップから復元する', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade400),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('閉じる')),
          ],
        );
      },
    );
  }

  void _showRestorePasteDialog() {
    final TextEditingController pasteController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('バックアップデータのインポート', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('保存してあったバックアップ用のテキスト文字列を、以下にそのまま貼り付けてください。', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 10),
              TextField(
                controller: pasteController,
                maxLines: 5,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '[{"name":"全般", "books":...}]',
                ),
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('キャンセル')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () {
                final inputJson = pasteController.text.trim();
                if (inputJson.isEmpty) return;

                try {
                  final List<dynamic> decoded = json.decode(inputJson);
                  
                  if (decoded.isNotEmpty && decoded[0] is Map && decoded[0].containsKey('name')) {
                    setState(() {
                      _bookshelves = decoded.map((shelf) {
                        final List<dynamic> booksList = shelf['books'] ?? [];
                        return {
                          'name': shelf['name'] as String,
                          'books': booksList.map((b) => Map<String, dynamic>.from(b)).toList(),
                        };
                      }).toList();
                      _selectedShelfIndex = 0;
                    });
                    
                    _saveBookshelvesToDevice();
                    Navigator.of(context).pop();
                    
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('🎉 本棚データの復元に成功しました！')),
                    );
                  } else {
                    throw const FormatException('不正な本棚フォーマットです');
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('❌ 復元に失敗しました。正しいデータか確認してください: $e')),
                  );
                }
              },
              child: const Text('データをインポートして上書き復元', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _createNewShelf() {
    final name = _newShelfController.text.trim();
    if (name.isEmpty) return;

    setState(() {
      _bookshelves.add({
        'name': name,
        'books': <Map<String, dynamic>>[],
      });
      _selectedShelfIndex = _bookshelves.length - 1;
      _newShelfController.clear();
    });
    _saveBookshelvesToDevice();
    if (mounted) Navigator.of(context).pop();
  }

  String _guessVolumeNumber(String title) {
    final RegExp regex = RegExp(r'(\d+)([巻冊話])?|([一二三四五六七八九十百]+)巻');
    final match = regex.allMatches(title);
    if (match.isNotEmpty) {
      return match.last.group(0) ?? '1巻';
    }
    return '1巻';
  }

  void _checkDuplicate(String title, String currentVolume) {
    bool found = false;
    String shelfName = '';

    for (var shelf in _bookshelves) {
      final List<dynamic> booksList = shelf['books'] ?? [];
      for (var b in booksList) {
        final book = Map<String, dynamic>.from(b);
        if (book['series'] != null) {
          if (title.contains(book['series']) && (book['volumes'] as List).contains(currentVolume)) {
            found = true;
            shelfName = shelf['name'];
            break;
          }
        } else if (book['title'] == title) {
          found = true;
          shelfName = shelf['name'];
          break;
        }
      }
      if (found) break;
    }

    setState(() {
      _isAlreadyOwned = found;
      _ownedShelfName = shelfName;
    });
  }

  void _executeSearch() {
    final inputIsbn = _isbnController.text.trim();
    if (inputIsbn.isNotEmpty) {
      searchBook(inputIsbn);
    }
  }

  Future<void> searchBook(String isbn) async {
    setState(() {
      _isLoading = true;
      _bookTitle = '';
      _bookAuthors = '';
      _scannedIsbn = isbn;
      _isAlreadyOwned = false;
      _ownedShelfName = '';
      _detectedVolume = '';
    });

    final url = Uri.parse('https://api.openbd.jp/v1/get?isbn=$isbn');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        if (data.isNotEmpty && data[0] != null) {
          final summary = data[0]['summary'];
          final fetchedTitle = summary['title'] ?? 'タイトル不明';
          final fetchedAuthor = summary['author'] ?? '著者不明';

          String apiVolume = '';
          final onix = data[0]['onix'];
          if (onix != null) {
            try {
              final partNumber = onix['DescriptiveDetail']['Collection'][0]['TitleDetail']['TitleElement'][0]['PartNumber'];
              if (partNumber != null) apiVolume = partNumber.toString().trim();
            } catch (_) {}
          }

          final finalVolume = apiVolume.isNotEmpty ? '${apiVolume}巻' : _guessVolumeNumber(fetchedTitle);

          setState(() {
            _bookTitle = fetchedTitle;
            _bookAuthors = fetchedAuthor;
            _detectedVolume = finalVolume;
          });

          _checkDuplicate(fetchedTitle, finalVolume);
        } else {
          setState(() { _bookTitle = '日本のデータベースに本が見つかりませんでした'; });
        }
      } else {
        setState(() { _bookTitle = '通信エラーが発生しました'; });
      }
    } catch (e) {
      setState(() { _bookTitle = '解読エラーが発生しました: $e'; });
    } finally {
      setState(() { _isLoading = false; });
    }
  }

  Future<void> _fetchBulkIsbns() async {
    final text = _bulkIsbnController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _isBulkLoading = true;
      for (var item in _bulkResultList) {
        item.dispose();
      }
      _bulkResultList = [];
    });

    final RegExp isbnRegex = RegExp(r'[0-9]{13}');
    final matches = isbnRegex.allMatches(text);
    final isbns = matches.map((m) => m.group(0)!).toSet().toList();

    if (isbns.isEmpty) {
      setState(() { _isBulkLoading = false; });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('有効な13桁のISBNが見つかりませんでした。')),
        );
      }
      return;
    }

    final url = Uri.parse('https://api.openbd.jp/v1/get?isbn=${isbns.join(',')}');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        List<BulkBookData> tempItems = [];

        for (var bookData in data) {
          if (bookData == null || bookData['summary'] == null) continue;
          final summary = bookData['summary'];
          final isbn = summary['isbn'] ?? '';
          final title = summary['title'] ?? 'タイトル不明';
          final author = summary['author'] ?? '著者不明';

          String apiVolume = '';
          try {
            final partNumber = bookData['onix']['DescriptiveDetail']['Collection'][0]['TitleDetail']['TitleElement'][0]['PartNumber'];
            if (partNumber != null) apiVolume = partNumber.toString().trim();
          } catch (_) {}

          final guessedVol = apiVolume.isNotEmpty ? '${apiVolume}巻' : _guessVolumeNumber(title);

          tempItems.add(BulkBookData(
            isbn: isbn,
            title: title,
            author: author,
            initialVolume: guessedVol,
          ));
        }

        setState(() {
          _bulkResultList = tempItems;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('一括解析エラー: $e')),
        );
      }
    } finally {
      setState(() { _isBulkLoading = false; });
    }
  }

  void _executeBulkNormalSave() {
    if (_bulkResultList.isEmpty) return;

    setState(() {
      final currentShelfBooks = _bookshelves[_selectedShelfIndex]['books'] as List<Map<String, dynamic>>;

      for (var book in _bulkResultList) {
        currentShelfBooks.add({
          'title': book.title,
          'author': book.author,
          'isbn': book.isbn,
        });
      }

      final count = _bulkResultList.length;
      _clearBulkState();
      final shelfName = _bookshelves[_selectedShelfIndex]['name'];
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('解析結果の$count冊を「$shelfName」本棚へ通常登録しました！')),
        );
      }
    });
    _saveBookshelvesToDevice();
  }

  void _showBulkSeriesSelectionDialog() {
    if (_bulkResultList.isEmpty) return;

    final currentShelfBooks = _bookshelves[_selectedShelfIndex]['books'] as List<Map<String, dynamic>>;
    final existingSeries = currentShelfBooks
        .where((b) => b['series'] != null)
        .map((b) => b['series'] as String)
        .toList();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('まとめてシリーズ登録設定', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('1. 各本の巻数調整（手動修正可能）：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueGrey)),
                const SizedBox(height: 5),
                Expanded(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _bulkResultList.length,
                    itemBuilder: (context, index) {
                      final book = _bulkResultList[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Text(book.title, style: const TextStyle(fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 1,
                              child: TextField(
                                controller: book.volumeController,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                  isDense: true,
                                ),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const Divider(height: 20),
                const Text('2. 登録先シリーズを選択：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueGrey)),
                const SizedBox(height: 5),
                
                Expanded(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.add_box, color: Colors.green),
                        title: const Text('新しいシリーズとして一括登録', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 13)),
                        onTap: () {
                          Navigator.of(context).pop();
                          _showBulkNewSeriesNameDialog();
                        },
                      ),
                      const Divider(),
                      if (existingSeries.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Text('既存のシリーズはありません', style: TextStyle(color: Colors.grey, fontSize: 12)),
                        ),
                      ...existingSeries.map((seriesName) => Card(
                        margin: const EdgeInsets.symmetric(vertical: 2),
                        child: ListTile(
                          dense: true,
                          leading: const Icon(Icons.folder, color: Colors.amber, size: 20),
                          title: Text(seriesName, style: const TextStyle(fontSize: 13)),
                          onTap: () {
                            Navigator.of(context).pop();
                            _executeBulkSeriesSave(seriesName);
                          },
                        ),
                      )),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('キャンセル')),
          ],
        );
      },
    );
  }

  void _showBulkNewSeriesNameDialog() {
    _seriesNameEditController.text = _bulkResultList.isNotEmpty ? _bulkResultList.first.title : '';

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('新規一括シリーズ名を入力', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _seriesNameEditController,
                autofocus: true,
                decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'シリーズ名'),
              ),
              const SizedBox(height: 5),
              const Text('※各書籍は上で調整した巻数で登録されます', style: TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('キャンセル')),
            ElevatedButton(
              onPressed: () {
                final inputName = _seriesNameEditController.text.trim();
                if (inputName.isNotEmpty) {
                  Navigator.of(context).pop();
                  _executeBulkSeriesSave(inputName);
                }
              },
              child: const Text('確定して一括登録'),
            ),
          ],
        );
      },
    );
  }

  void _executeBulkSeriesSave(String seriesName) {
    setState(() {
      final currentShelfBooks = _bookshelves[_selectedShelfIndex]['books'] as List<Map<String, dynamic>>;
      String defaultAuthor = _bulkResultList.isNotEmpty ? _bulkResultList.first.author : '著者不明';

      int existingIndex = currentShelfBooks.indexWhere((book) => book['series'] == seriesName);

      if (existingIndex != -1) {
        final List<dynamic> volumes = currentShelfBooks[existingIndex]['volumes'];
        for (var book in _bulkResultList) {
          final volText = book.volumeController.text.trim();
          if (volText.isNotEmpty && !volumes.contains(volText)) {
            volumes.add(volText);
          }
        }
        volumes.sort((a, b) {
          final numA = int.tryParse(a.replaceAll(RegExp(r'\D'), '')) ?? 0;
          final numB = int.tryParse(b.replaceAll(RegExp(r'\D'), '')) ?? 0;
          return numA.compareTo(numB);
        });
      } else {
        List<String> initialVolumes = [];
        for (var book in _bulkResultList) {
          final volText = book.volumeController.text.trim();
          if (volText.isNotEmpty && !initialVolumes.contains(volText)) {
            initialVolumes.add(volText);
          }
        }
        initialVolumes.sort((a, b) {
          final numA = int.tryParse(a.replaceAll(RegExp(r'\D'), '')) ?? 0;
          final numB = int.tryParse(b.replaceAll(RegExp(r'\D'), '')) ?? 0;
          return numA.compareTo(numB);
        });

        currentShelfBooks.add({
          'series': seriesName,
          'author': defaultAuthor,
          'volumes': initialVolumes,
        });
      }

      _clearBulkState();
      final shelfName = _bookshelves[_selectedShelfIndex]['name'];
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('シリーズ「$seriesName」として、「$shelfName」本棚へ一括登録しました！')),
        );
      }
    });

    _saveBookshelvesToDevice();
  }

  void _clearBulkState() {
    for (var item in _bulkResultList) {
      item.dispose();
    }
    _bulkResultList = [];
    _bulkIsbnController.clear();
  }

  void _saveSingleToBookshelf() {
    setState(() {
      final currentShelfBooks = _bookshelves[_selectedShelfIndex]['books'] as List<Map<String, dynamic>>;
      currentShelfBooks.add({
        'title': _bookTitle,
        'author': _bookAuthors,
        'isbn': _scannedIsbn,
      });
      _finishRegistration();
    });
  }

  void _saveAsSeries(String seriesName, String finalVolume) {
    setState(() {
      final currentShelfBooks = _bookshelves[_selectedShelfIndex]['books'] as List<Map<String, dynamic>>;
      
      int existingIndex = currentShelfBooks.indexWhere((book) => book['series'] == seriesName);

      if (existingIndex != -1) {
        final List<dynamic> volumes = currentShelfBooks[existingIndex]['volumes'];
        if (!volumes.contains(finalVolume)) {
          volumes.add(finalVolume);
          volumes.sort((a, b) {
            final numA = int.tryParse(a.replaceAll(RegExp(r'\D'), '')) ?? 0;
            final numB = int.tryParse(b.replaceAll(RegExp(r'\D'), '')) ?? 0;
            return numA.compareTo(numB);
          });
        }
      } else {
        currentShelfBooks.add({
          'series': seriesName,
          'author': _bookAuthors,
          'volumes': [finalVolume],
        });
      }
      _finishRegistration();
    });
  }

  void _finishRegistration() {
    final shelfName = _bookshelves[_selectedShelfIndex]['name'];
    _bookTitle = '「$shelfName」本棚に保存しました！';
    _bookAuthors = '';
    _isAlreadyOwned = false;
    _ownedShelfName = '';
    _isbnController.clear();
    _saveBookshelvesToDevice();
  }

  List<String> _formatVolumeRanges(List<dynamic> rawVolumes) {
    if (rawVolumes.isEmpty) return [];
    List<int> numbers = [];
    List<String> textVolumes = [];

    for (var v in rawVolumes) {
      final String vStr = v.toString();
      final String onlyNum = vStr.replaceAll(RegExp(r'\D'), '');
      final int? num = int.tryParse(onlyNum);
      if (num != null && (vStr.contains('巻') || RegExp(r'^\d+$').hasMatch(vStr))) {
        numbers.add(num);
      } else {
        textVolumes.add(vStr.replaceAll('巻', ''));
      }
    }

    numbers = numbers.toSet().toList();
    numbers.sort();
    
    List<String> formattedRanges = [];
    if (numbers.isNotEmpty) {
      int start = numbers[0];
      int prev = numbers[0];

      for (int i = 1; i < numbers.length; i++) {
        if (numbers[i] == prev + 1) {
          prev = numbers[i];
        } else {
          if (start == prev) {
            formattedRanges.add('$start');
          } else {
            formattedRanges.add('$start〜$prev');
          }
          start = numbers[i];
          prev = numbers[i];
        }
      }
      if (start == prev) {
        formattedRanges.add('$start');
      } else {
        formattedRanges.add('$start〜$prev');
      }
    }
    return [...formattedRanges, ...textVolumes];
  }

  void _showSeriesSelectionDialog() {
    _volumeEditController.text = _detectedVolume;

    final currentShelfBooks = _bookshelves[_selectedShelfIndex]['books'] as List<Map<String, dynamic>>;
    final existingSeries = currentShelfBooks
        .where((b) => b['series'] != null)
        .map((b) => b['series'] as String)
        .toList();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('シリーズ登録設定', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('1. 巻数の確認・修正：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey)),
                const SizedBox(height: 5),
                TextField(
                  controller: _volumeEditController,
                  decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                ),
                const SizedBox(height: 15),
                const Divider(),
                const SizedBox(height: 5),
                const Text('2. 登録先シリーズを選択：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey)),
                const SizedBox(height: 5),
                
                Expanded(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.add_box, color: Colors.green),
                        title: const Text('新しいシリーズとして登録', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                        onTap: () {
                          final finalVolume = _volumeEditController.text.trim();
                          if (finalVolume.isEmpty) return;
                          Navigator.of(context).pop();
                          _showNewSeriesNameDialog(finalVolume);
                        },
                      ),
                      const Divider(),
                      if (existingSeries.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Text('既存のシリーズはありません', style: TextStyle(color: Colors.grey, fontSize: 12)),
                        ),
                      ...existingSeries.map((seriesName) => Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          leading: const Icon(Icons.folder, color: Colors.amber),
                          title: Text(seriesName),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            final finalVolume = _volumeEditController.text.trim();
                            if (finalVolume.isEmpty) return;
                            Navigator.of(context).pop();
                            _saveAsSeries(seriesName, finalVolume);
                          },
                        ),
                      )),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('キャンセル')),
          ],
        );
      },
    );
  }

  void _showNewSeriesNameDialog(String finalVolume) {
    _seriesNameEditController.text = _bookTitle;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('新規シリーズ名を入力', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _seriesNameEditController,
                autofocus: true,
                decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'シリーズ名'),
              ),
              const SizedBox(height: 8),
              Text('※登録される巻数: $finalVolume', style: const TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.bold)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('キャンセル')),
            ElevatedButton(
              onPressed: () {
                final inputName = _seriesNameEditController.text.trim();
                if (inputName.isNotEmpty) {
                  Navigator.of(context).pop();
                  _saveAsSeries(inputName, finalVolume);
                }
              },
              child: const Text('確定して登録'),
            ),
          ],
        );
      },
    );
  }

  void _deleteBook(int bookIndex) {
    setState(() {
      final currentBooks = _bookshelves[_selectedShelfIndex]['books'] as List<Map<String, dynamic>>;
      currentBooks.removeAt(bookIndex);
    });
    _saveBookshelvesToDevice();
    if (mounted) Navigator.of(context).pop();
  }

  void _moveBook(int currentBookIndex, int targetShelfIndex) {
    setState(() {
      final currentBooks = _bookshelves[_selectedShelfIndex]['books'] as List<Map<String, dynamic>>;
      final bookToMove = currentBooks.removeAt(currentBookIndex);
      final targetBooks = _bookshelves[targetShelfIndex]['books'] as List<Map<String, dynamic>>;
      
      if (bookToMove['series'] != null) {
        int existingIndex = targetBooks.indexWhere((b) => b['series'] == bookToMove['series']);
        if (existingIndex != -1) {
          final List<dynamic> targetVolumes = targetBooks[existingIndex]['volumes'];
          for (var v in bookToMove['volumes']) {
            if (!targetVolumes.contains(v)) targetVolumes.add(v);
          }
          targetVolumes.sort((a, b) {
            final numA = int.tryParse(a.replaceAll(RegExp(r'\D'), '')) ?? 0;
            final numB = int.tryParse(b.replaceAll(RegExp(r'\D'), '')) ?? 0;
            return numA.compareTo(numB);
          });
        } else {
          targetBooks.add(bookToMove);
        }
      } else {
        targetBooks.add(bookToMove);
      }
    });
    _saveBookshelvesToDevice();
    if (mounted) Navigator.of(context).pop();
  }

  void _showEditBookDialog(int bookIndex, Map<String, dynamic> book) {
    final isSeries = book['series'] != null;
    
    _editTitleController.text = isSeries ? book['series'] : book['title'];
    _editAuthorController.text = book['author'] ?? '';

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: const [
              Icon(Icons.edit_note, color: Colors.blue),
              SizedBox(width: 5),
              Text('書籍情報の編集', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _editTitleController,
                decoration: InputDecoration(
                  labelText: isSeries ? 'シリーズ名' : 'タイトル',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: _editAuthorController,
                decoration: const InputDecoration(
                  labelText: '著者名',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('キャンセル'),
            ),
            ElevatedButton(
              onPressed: () {
                final String newTitle = _editTitleController.text.trim();
                final String newAuthor = _editAuthorController.text.trim();

                if (newTitle.isEmpty) return;

                setState(() {
                  final currentBooks = _bookshelves[_selectedShelfIndex]['books'] as List<Map<String, dynamic>>;
                  if (isSeries) {
                    currentBooks[bookIndex]['series'] = newTitle;
                  } else {
                    currentBooks[bookIndex]['title'] = newTitle;
                  }
                  currentBooks[bookIndex]['author'] = newAuthor;
                });

                _saveBookshelvesToDevice();
                Navigator.of(context).pop();
                Navigator.of(context).pop();
                
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('書籍情報を更新しました！')),
                );
              },
              child: const Text('保存する'),
            ),
          ],
        );
      },
    );
  }

  void _showBookMenu(int bookIndex, Map<String, dynamic> book) {
    final isSeries = book['series'] != null;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(isSeries ? book['series'] : book['title'], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(isSeries ? 'このシリーズをどうしますか？' : 'この本をどうしますか？', style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 15),
              
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.blue),
                title: const Text('情報を手動で編集する', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                onTap: () => _showEditBookDialog(bookIndex, book),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
              const Divider(),
              const SizedBox(height: 5),

              if (_bookshelves.length > 1) ...[
                const Text('別の本棚に移動する：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 5,
                  children: _bookshelves.asMap().entries.map((entry) {
                    if (entry.key == _selectedShelfIndex) return const SizedBox();
                    return ElevatedButton.icon(
                      onPressed: () => _moveBook(bookIndex, entry.key),
                      icon: const Icon(Icons.drive_file_move, size: 16),
                      label: Text(entry.value['name']),
                    );
                  }).toList(),
                ),
                const Divider(height: 30),
              ],
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: () => _deleteBook(bookIndex),
              icon: const Icon(Icons.delete, color: Colors.red),
              label: Text(isSeries ? 'シリーズごと削除' : '本棚から削除', style: const TextStyle(color: Colors.red)),
            ),
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('閉じる')),
          ],
        );
      },
    );
  }

  List<Map<String, dynamic>> _getFilteredBooks() {
    List<Map<String, dynamic>> results = [];
    
    for (var shelf in _bookshelves) {
      final List<dynamic> books = shelf['books'] ?? [];
      for (int i = 0; i < books.length; i++) {
        final book = Map<String, dynamic>.from(books[i]);
        final String title = (book['title'] ?? '').toString().toLowerCase();
        final String author = (book['author'] ?? '').toString().toLowerCase();
        final String series = (book['series'] ?? '').toString().toLowerCase();

        if (title.contains(_searchQuery) || author.contains(_searchQuery) || series.contains(_searchQuery)) {
          results.add({
            ...book,
            '_originalShelfName': shelf['name'],
            '_originalIndex': i,
          });
        }
      }
    }
    return results;
  }

  void _startContinuousScan() async {
    List<String> temporaryScannedIsbns = [];
    String lastScannedIsbn = '';

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => StatefulBuilder(
          builder: (context, setModalState) {
            return Scaffold(
              appBar: AppBar(
                title: const Text('超高速・連続スキャンモード', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                backgroundColor: Colors.orange.shade100,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.check_circle, color: Colors.green, size: 30),
                    onPressed: () {
                      Navigator.of(context).pop(temporaryScannedIsbns);
                    },
                  ),
                  const SizedBox(width: 10),
                ],
              ),
              body: Column(
                children: [
                  Expanded(
                    flex: 6,
                    child: AiBarcodeScanner(
                      // 💡 エラーの原因だった canPop: false を削除しました。
                      // 代わりにonDetect内の条件分岐だけで安全に連続取得を制御します。
                      onDetect: (BarcodeCapture capture) {
                        final String? scannedValue = capture.barcodes.first.rawValue;
                        if (scannedValue != null && scannedValue.startsWith('978')) {
                          if (scannedValue != lastScannedIsbn) {
                            lastScannedIsbn = scannedValue;
                            if (!temporaryScannedIsbns.contains(scannedValue)) {
                              setModalState(() {
                                temporaryScannedIsbns.add(scannedValue);
                              });
                            }
                          }
                        }
                      },
                    ),
                  ),
                  Expanded(
                    flex: 4,
                    child: Container(
                      color: Colors.grey.shade900,
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '🎯 スキャン数: ${temporaryScannedIsbns.length} 冊',
                                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              ElevatedButton.icon(
                                onPressed: temporaryScannedIsbns.isEmpty ? null : () {
                                  Navigator.of(context).pop(temporaryScannedIsbns);
                                },
                                icon: const Icon(Icons.save_alt),
                                label: const Text('確定して解析へ'),
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                              )
                            ],
                          ),
                          const SizedBox(height: 10),
                          const Text('スキャン済みのISBN一覧:', style: TextStyle(color: Colors.grey, fontSize: 12)),
                          Expanded(
                            child: temporaryScannedIsbns.isEmpty
                                ? const Center(child: Text('本のバーコード（978から始まる方）をカメラにかざしてください', style: TextStyle(color: Colors.grey, fontSize: 12)))
                                : ListView.builder(
                                    itemCount: temporaryScannedIsbns.length,
                                    itemBuilder: (context, idx) {
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 2.0),
                                        child: Text(
                                          '   •  ${temporaryScannedIsbns[idx]}',
                                          style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace', fontSize: 14),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ).then((result) {
      if (result != null && result is List<String> && result.isNotEmpty) {
        _bulkIsbnController.text = result.join('\n');
        _tabController.animateTo(1);
        _fetchBulkIsbns();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentShelf = _bookshelves[_selectedShelfIndex];
    final currentBooks = currentShelf['books'] as List<Map<String, dynamic>>;

    final bool isSearching = _searchQuery.isNotEmpty;
    final List<Map<String, dynamic>> filteredBooks = isSearching ? _getFilteredBooks() : [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('マイ蔵書管理'),
        backgroundColor: Colors.blue.shade100,
        actions: [
          IconButton(
            icon: const Icon(Icons.create_new_folder),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('新しい本棚を作成'),
                  content: TextField(
                    controller: _newShelfController,
                    decoration: const InputDecoration(hintText: '例: 小説、漫画'),
                    autofocus: true,
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('キャンセル')),
                    ElevatedButton(onPressed: _createNewShelf, child: const Text('作成')),
                  ],
                ),
              );
            },
          )
        ],
      ),
      body: Column(
        children: <Widget>[
          Container(
            color: Colors.grey.shade50,
            padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 5.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: _showBackupRestoreDialog,
                  icon: const Icon(Icons.settings, size: 16, color: Colors.blueGrey),
                  label: const Text('⚙️ データ管理', style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
                ),
                Row(
                  children: [
                    const Text('保存先： ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    DropdownButton<int>(
                      value: _selectedShelfIndex,
                      style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold),
                      items: _bookshelves.asMap().entries.map((entry) {
                        return DropdownMenuItem<int>(
                          value: entry.key,
                          child: Text('${entry.value['name']} (${entry.value['books'].length})'),
                        );
                      }).toList(),
                      onChanged: (int? newValue) {
                        if (newValue != null) {
                          setState(() { _selectedShelfIndex = newValue; });
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),

          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(icon: Icon(Icons.looks_one), text: '1冊ずつ登録'),
              Tab(icon: Icon(Icons.dynamic_feed), text: 'まとめて登録'),
            ],
          ),

          Expanded(
            flex: 4,
            child: TabBarView(
              controller: _tabController,
              children: [
                Container(
                  padding: const EdgeInsets.all(12.0),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _isbnController,
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.search,
                              onSubmitted: (value) => _executeSearch(),
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                labelText: 'ISBN（13桁）を入力',
                                prefixIcon: Icon(Icons.edit),
                                contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton(onPressed: _executeSearch, child: const Text('検索')),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (_isLoading)
                        const Center(child: CircularProgressIndicator())
                      else ...[
                        if (_isAlreadyOwned)
                          Card(
                            color: Colors.amber.shade100,
                            margin: const EdgeInsets.symmetric(vertical: 5),
                            child: Padding(
                              padding: const EdgeInsets.all(6.0),
                              child: Text(
                                '⚠️ 【所持済み】「$_ownedShelfName」にあります！',
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.brown, fontSize: 12),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        Text(_bookTitle, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                        if (_detectedVolume.isNotEmpty)
                          Text('（自動検出巻数: $_detectedVolume）', style: const TextStyle(fontSize: 11, color: Colors.blueGrey), textAlign: TextAlign.center),
                        Text(_bookAuthors, style: const TextStyle(fontSize: 12, color: Colors.blueGrey), textAlign: TextAlign.center),
                        const SizedBox(height: 8),
                        if (_bookTitle.isNotEmpty && !_bookTitle.contains('保存しました') && _bookTitle != '日本のデータベースに本が見つかりませんでした')
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ElevatedButton(
                                onPressed: _saveSingleToBookshelf,
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade50),
                                child: const Text('通常登録'),
                              ),
                              const SizedBox(width: 15),
                              ElevatedButton(
                                onPressed: _showSeriesSelectionDialog,
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade600),
                                child: const Text('シリーズ登録', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                      ]
                    ],
                  ),
                ),

                Container(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    children: [
                      if (_bulkResultList.isEmpty) ...[
                        Expanded(
                          child: TextField(
                            controller: _bulkIsbnController,
                            maxLines: null,
                            expands: true,
                            keyboardType: TextInputType.multiline,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              hintText: 'ここに複数のISBNコードを貼り付け...\n（改行、スペース、カンマ区切りに対応）',
                            ),
                          ),
                        ),
                        const SizedBox(height: 5),
                        ElevatedButton.icon(
                          onPressed: _isBulkLoading ? null : _fetchBulkIsbns,
                          icon: _isBulkLoading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.analytics),
                          label: const Text('一括解析スタート'),
                        ),
                      ] else ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('📦 解析結果: ${_bulkResultList.length}冊', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                            TextButton(
                              onPressed: () => setState(() => _bulkResultList = []),
                              child: const Text('入力をやり直す', style: TextStyle(fontSize: 12)),
                            )
                          ],
                        ),
                        Expanded(
                          child: ListView.builder(
                            itemCount: _bulkResultList.length,
                            itemBuilder: (context, index) {
                              final book = _bulkResultList[index];
                              return ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 5),
                                leading: const Icon(Icons.check_circle, color: Colors.green, size: 18),
                                title: Text(book.title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                                subtitle: Text(book.author, style: const TextStyle(fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _executeBulkNormalSave,
                                icon: const Icon(Icons.bookmark_add),
                                label: const Text('まとめて通常登録', style: TextStyle(fontSize: 12)),
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade50),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _showBulkSeriesSelectionDialog,
                                icon: const Icon(Icons.library_books, color: Colors.white),
                                label: const Text('まとめてシリーズ登録', style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade600),
                              ),
                            ),
                          ],
                        ),
                      ]
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          Expanded(
            flex: 5,
            child: Padding(
              padding: const EdgeInsets.all(10.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'タイトル・著者・シリーズ名で検索...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: isSearching
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () => _searchController.clear(),
                              )
                            : null,
                        border: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(10.0)),
                        ),
                        contentPadding: const EdgeInsets.symmetric(vertical: 6.0),
                      ),
                    ),
                  ),
                  
                  Text(
                    isSearching
                        ? '🔍 全本棚からの検索結果 (${filteredBooks.length}項目)'
                        : ' 📂 現在の本棚: ${currentShelf['name']} (${currentBooks.length}項目)',
                    style: TextStyle(
                      fontSize: 14, 
                      fontWeight: FontWeight.bold, 
                      color: isSearching ? Colors.purple : Colors.blue,
                    ),
                  ),
                  const SizedBox(height: 5),
                  
                  Expanded(
                    child: isSearching
                        ? (filteredBooks.isEmpty
                            ? const Center(child: Text('キーワードに一致する本はありません。'))
                            : ListView.builder(
                                itemCount: filteredBooks.length,
                                itemBuilder: (context, index) {
                                  final book = filteredBooks[index];
                                  final isSeries = book['series'] != null;
                                  final List<dynamic> rawVols = book['volumes'] ?? [];
                                  final List<String> formattedVols = isSeries ? _formatVolumeRanges(rawVols) : [];
                                  final String originShelf = book['_originalShelfName'] ?? '';
                                  
                                  return Card(
                                    color: Colors.purple.shade50.withOpacity(0.3),
                                    child: ListTile(
                                      dense: true,
                                      leading: CircleAvatar(
                                        backgroundColor: isSeries ? Colors.purple.shade100 : Colors.grey.shade200,
                                        child: Icon(isSeries ? Icons.collections_bookmark : Icons.book, color: isSeries ? Colors.purple : Colors.grey, size: 16),
                                      ),
                                      title: Text(isSeries ? book['series'] : book['title'], style: const TextStyle(fontWeight: FontWeight.bold)),
                                      subtitle: Text('${book['author'] ?? ''}  [本棚: $originShelf]', style: const TextStyle(fontSize: 11)),
                                      trailing: isSeries
                                          ? Wrap(
                                              spacing: 4,
                                              children: formattedVols.map((v) => Chip(
                                                label: Text(v, style: const TextStyle(fontSize: 10)),
                                                padding: EdgeInsets.zero,
                                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                backgroundColor: Colors.purple.shade50,
                                              )).toList(),
                                            )
                                          : const Chip(label: Text('単行本', style: TextStyle(fontSize: 10))),
                                      onTap: () {
                                        final int targetShelfIdx = _bookshelves.indexWhere((s) => s['name'] == originShelf);
                                        if (targetShelfIdx != -1) {
                                          setState(() {
                                            _selectedShelfIndex = targetShelfIdx;
                                          });
                                          _showBookMenu(book['_originalIndex'], book);
                                        }
                                      },
                                    ),
                                  );
                                },
                              ))
                        : (currentBooks.isEmpty
                            ? const Center(child: Text('この本棚は空っぽです。'))
                            : ListView.builder(
                                itemCount: currentBooks.length,
                                itemBuilder: (context, index) {
                                  final book = currentBooks[index];
                                  final isSeries = book['series'] != null;
                                  final List<dynamic> rawVols = book['volumes'] ?? [];
                                  final List<String> formattedVols = isSeries ? _formatVolumeRanges(rawVols) : [];
                                  
                                  return Card(
                                    child: ListTile(
                                      dense: true,
                                      leading: CircleAvatar(
                                        backgroundColor: isSeries ? Colors.blue.shade100 : Colors.grey.shade200,
                                        child: Icon(isSeries ? Icons.collections_bookmark : Icons.book, color: isSeries ? Colors.blue : Colors.grey, size: 16),
                                      ),
                                      title: Text(isSeries ? book['series'] : book['title'], style: const TextStyle(fontWeight: FontWeight.bold)),
                                      subtitle: Text(book['author'] ?? '', style: const TextStyle(fontSize: 11)),
                                      trailing: isSeries
                                          ? Wrap(
                                              spacing: 4,
                                              children: formattedVols.map((v) => Chip(
                                                label: Text(v, style: const TextStyle(fontSize: 10)),
                                                padding: EdgeInsets.zero,
                                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                backgroundColor: Colors.blue.shade50,
                                              )).toList(),
                                            )
                                          : const Chip(label: Text('単行本', style: TextStyle(fontSize: 10))),
                                      onTap: () => _showBookMenu(index, book),
                                    ),
                                  );
                                },
                              )),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _startContinuousScan,
        icon: const Icon(Icons.flash_on),
        label: const Text('超高速スキャン'),
        backgroundColor: Colors.orange.shade400,
      ),
    );
  }
}
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class AppDatabase {
  static final AppDatabase instance = AppDatabase._init();
  static Database? _database;

  AppDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('vittix_chat_history.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        server_id TEXT NOT NULL,
        target TEXT NOT NULL,
        sender TEXT NOT NULL,
        text TEXT NOT NULL,
        time TEXT NOT NULL,
        is_me INTEGER NOT NULL DEFAULT 0,
        is_system INTEGER NOT NULL DEFAULT 0,
        type TEXT NOT NULL DEFAULT 'normal'
      )
    ''');
    
    // Create indexes to optimize targeted lookups and sorting by time
    await db.execute('CREATE INDEX idx_server_target ON messages (server_id, target)');
    await db.execute('CREATE INDEX idx_time ON messages (time)');
  }

  Future<void> close() async {
    final db = await instance.database;
    db.close();
  }
}
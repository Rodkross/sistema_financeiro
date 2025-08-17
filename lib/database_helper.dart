import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() {
    return _instance;
  }

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'financeiro.db');

    return await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE contas(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            descricao TEXT,
            valor REAL,
            data TEXT,
            paga INTEGER DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE pagamentos(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            conta_id INTEGER,
            transacao_id TEXT,
            data_pagamento TEXT,
            meio_pagamento TEXT
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute("ALTER TABLE pagamentos ADD COLUMN transacao_id TEXT");
        }
      },
    );
  }

  Future<List<Map<String, dynamic>>> getContas() async {
    Database db = await database;
    return await db.query('contas');
  }

  Future<List<Map<String, dynamic>>> getPagamentos() async {
    Database db = await database;
    return await db.query('pagamentos');
  }

  Future<List<Map<String, dynamic>>> getContasByFilter({
    DateTime? startDate,
    DateTime? endDate,
    int? status,
  }) async {
    Database db = await database;
    String? whereClause;
    List<dynamic> whereArgs = [];

    if (startDate != null && endDate != null) {
      whereClause = 'data BETWEEN ? AND ?';
      whereArgs.add(startDate.toIso8601String());
      whereArgs.add(endDate.toIso8601String());
    }

    if (status != null) {
      if (whereClause != null) {
        whereClause += ' AND paga = ?';
      } else {
        whereClause = 'paga = ?';
      }
      whereArgs.add(status);
    }
    
    return await db.query(
      'contas',
      where: whereClause,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: 'data ASC'
    );
  }

  Future<int> insertConta(Map<String, dynamic> conta) async {
    try {
      Database db = await database;
      return await db.insert('contas', conta);
    } catch (e) {
      print('Erro ao inserir conta no SQLite: $e');
      return -1;
    }
  }

  Future<int> updateConta(Map<String, dynamic> conta) async {
    try {
      Database db = await database;
      final Map<String, dynamic> contaSemNulos = conta..removeWhere((key, value) => value == null);
      return await db.update(
        'contas',
        contaSemNulos,
        where: 'id = ?',
        whereArgs: [contaSemNulos['id']],
      );
    } catch (e) {
      print('Erro ao atualizar conta no SQLite: $e');
      return -1;
    }
  }

  Future<int> deleteConta(int id) async {
    try {
      Database db = await database;
      return await db.delete(
        'contas',
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e) {
      print('Erro ao deletar conta no SQLite: $e');
      return -1;
    }
  }

  Future<int> insertPagamento(Map<String, dynamic> pagamento) async {
    try {
      Database db = await database;
      return await db.insert('pagamentos', pagamento);
    } catch (e) {
      print('Erro ao inserir pagamento no SQLite: $e');
      return -1;
    }
  }

  Future<List<Map<String, dynamic>>> getPagamentosPorData(DateTime data) async {
    Database db = await database;
    final startOfDay = DateTime(data.year, data.month, data.day).toIso8601String();
    final endOfDay = DateTime(data.year, data.month, data.day, 23, 59, 59).toIso8601String();

    final sql = '''
      SELECT
        P.transacao_id,
        P.data_pagamento,
        P.meio_pagamento,
        C.descricao,
        C.valor
      FROM pagamentos P
      INNER JOIN contas C ON P.conta_id = C.id
      WHERE P.data_pagamento BETWEEN ? AND ?
      ORDER BY P.data_pagamento DESC
    ''';
    
    return await db.rawQuery(sql, [startOfDay, endOfDay]);
  }

  Future<void> revertPagamento(String transacaoId) async {
    Database db = await database;
    try {
      await db.transaction((txn) async {
        final List<Map<String, dynamic>> pagamentos = await txn.query(
          'pagamentos',
          where: 'transacao_id = ?',
          whereArgs: [transacaoId],
        );
        for (var pagamento in pagamentos) {
          await txn.update(
            'contas',
            {'paga': 0},
            where: 'id = ?',
            whereArgs: [pagamento['conta_id']],
          );
        }
        await txn.delete(
          'pagamentos',
          where: 'transacao_id = ?',
          whereArgs: [transacaoId],
        );
      });
    } catch (e) {
      print('Erro ao reverter pagamento no SQLite: $e');
    }
  }
}
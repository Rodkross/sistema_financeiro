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
    
    //await deleteDatabase(path);

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
    );
  }

  // NOVO MÉTODO: Retorna todas as contas, pagas e não pagas
  Future<List<Map<String, dynamic>>> getContas() async {
    Database db = await database;
    return await db.query('contas');
  }

  // NOVO MÉTODO: Retorna todos os pagamentos
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
    Database db = await database;
    return await db.insert('contas', conta);
  }

  Future<int> updateConta(Map<String, dynamic> conta) async {
    Database db = await database;
    return await db.update(
      'contas',
      conta,
      where: 'id = ?',
      whereArgs: [conta['id']],
    );
  }

  Future<int> insertPagamento(Map<String, dynamic> pagamento) async {
    Database db = await database;
    return await db.insert('pagamentos', pagamento);
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
  }
}
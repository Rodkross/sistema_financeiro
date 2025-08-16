import 'package:cloud_firestore/cloud_firestore.dart';
import 'database_helper.dart';

class DatabaseService {
  final _dbHelper = DatabaseHelper();
  final _firestore = FirebaseFirestore.instance;

  // Sincroniza dados locais (SQLite) para a nuvem (Firestore)
  Future<void> _syncToCloud() async {
    // Busca todas as contas e pagamentos locais para sincronizar
    final contasToSync = await _dbHelper.getContas();
    final pagamentosToSync = await _dbHelper.getPagamentos();

    // Sincroniza contas
    for (var conta in contasToSync) {
      await _firestore.collection('contas').doc(conta['id'].toString()).set(conta);
    }

    // Sincroniza pagamentos
    for (var pagamento in pagamentosToSync) {
      await _firestore.collection('pagamentos').add(pagamento);
    }
  }

  // Sincroniza dados da nuvem (Firestore) para o local (SQLite)
  Future<void> _syncFromCloud() async {
    final contasSnapshot = await _firestore.collection('contas').get();
    for (var doc in contasSnapshot.docs) {
      final contaId = int.tryParse(doc.id);
      if (contaId != null) {
        final data = doc.data();
        await _dbHelper.updateConta({
          'id': contaId,
          ...data,
        });
      }
    }
  }

  // --- Métodos de CRUD que usam a lógica híbrida ---

  Future<void> insertConta(Map<String, dynamic> conta) async {
    final localId = await _dbHelper.insertConta(conta);
    conta['id'] = localId;
    await _firestore.collection('contas').doc(localId.toString()).set(conta);
  }

  Future<List<Map<String, dynamic>>> getContasByFilter({
    DateTime? startDate,
    DateTime? endDate,
    int? status,
  }) async {
    // Tenta sincronizar os dados da nuvem primeiro
    await _syncFromCloud();
    // Depois, retorna os dados locais
    return await _dbHelper.getContasByFilter(
      startDate: startDate,
      endDate: endDate,
      status: status,
    );
  }

  Future<int> updateConta(Map<String, dynamic> conta) async {
    final result = await _dbHelper.updateConta(conta);
    await _syncToCloud();
    return result;
  }

  Future<int> insertPagamento(Map<String, dynamic> pagamento) async {
    final result = await _dbHelper.insertPagamento(pagamento);
    await _firestore.collection('pagamentos').add(pagamento);
    return result;
  }
  
  Future<List<Map<String, dynamic>>> getPagamentosPorData(DateTime data) async {
    // Esta função busca diretamente do SQLite
    return await _dbHelper.getPagamentosPorData(data);
  }

  Future<void> revertPagamento(String transacaoId) async {
    // Reverte localmente e depois na nuvem
    await _dbHelper.revertPagamento(transacaoId);
    await _firestore.collection('pagamentos')
        .where('transacao_id', isEqualTo: transacaoId)
        .get()
        .then((snapshot) {
      final batch = _firestore.batch();
      for (var doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      return batch.commit();
    });
  }
}
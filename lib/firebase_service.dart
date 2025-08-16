import 'package:cloud_firestore/cloud_firestore.dart';

class FirebaseService {
  final _contasCollection = FirebaseFirestore.instance.collection('contas');
  final _pagamentosCollection = FirebaseFirestore.instance.collection('pagamentos');

  Future<void> syncUp(List<Map<String, dynamic>> contasToSync) async {
    final batch = FirebaseFirestore.instance.batch();
    for (var conta in contasToSync) {
      final docRef = _contasCollection.doc(conta['id'].toString());
      batch.set(docRef, conta);
    }
    await batch.commit();
  }

  Future<List<Map<String, dynamic>>> syncDown() async {
    final snapshot = await _contasCollection.get();
    return snapshot.docs.map((doc) => doc.data()).toList();
  }

  Future<void> savePayment(Map<String, dynamic> payment) async {
    await _pagamentosCollection.add(payment);
  }

  Future<void> revertPayment(String transacaoId) async {
    final payments = await _pagamentosCollection.where('transacao_id', isEqualTo: transacaoId).get();
    final batch = FirebaseFirestore.instance.batch();
    for (var doc in payments.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }
}
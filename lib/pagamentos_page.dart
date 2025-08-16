import 'package:flutter/material.dart';
import 'database_helper.dart';

class PagamentosPage extends StatefulWidget {
  const PagamentosPage({super.key});

  @override
  _PagamentosPageState createState() => _PagamentosPageState();
}

class _PagamentosPageState extends State<PagamentosPage> {
  final dbHelper = DatabaseHelper();
  List<Map<String, dynamic>> pagamentos = [];
  bool isLoading = false;
  
  DateTime? _selectedDate;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // A tela inicia vazia
  }

  Future<void> _fetchPagamentos() async {
    setState(() {
      isLoading = true;
      _errorMessage = null;
    });
    try {
      if (_selectedDate != null) {
        List<Map<String, dynamic>> listaPagamentos = await dbHelper.getPagamentosPorData(_selectedDate!);
        
        setState(() {
          pagamentos = listaPagamentos;
        });
      } else {
        pagamentos.clear();
      }
    } catch (e) {
      print('Erro ao carregar os pagamentos: $e');
      setState(() {
        _errorMessage = 'Não foi possível carregar os pagamentos. Verifique o console.';
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      _fetchPagamentos();
    }
  }

  Future<void> _showRevertPaymentDialog(String transacaoId) async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Confirmar Estorno'),
          content: const Text('Esta conta faz parte de um grupo. Deseja estornar todos os pagamentos da transação?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Confirmar'),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      try {
        await dbHelper.revertPagamento(transacaoId);
        _fetchPagamentos();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Transação estornada com sucesso!')),
        );
      } catch (e) {
        print('Erro ao estornar o pagamento: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Falha ao estornar o pagamento.')),
        );
      }
    }
  }
  
  // Função para agrupar pagamentos por transação
  Map<String, List<Map<String, dynamic>>> _groupPaymentsByTransaction() {
    Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var pagamento in pagamentos) {
      String transacaoId = pagamento['transacao_id'];
      if (!grouped.containsKey(transacaoId)) {
        grouped[transacaoId] = [];
      }
      grouped[transacaoId]!.add(pagamento);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    // Agrupa os pagamentos para a visualização
    final groupedPayments = _groupPaymentsByTransaction();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Histórico de Pagamentos'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: () => _selectDate(context),
          ),
          if (_selectedDate != null)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                setState(() {
                  _selectedDate = null;
                  pagamentos.clear();
                });
              },
            ),
        ],
      ),
      body: Column(
        children: [
          if (_selectedDate != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                'Filtrando por: ${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? Center(child: Text(_errorMessage!))
                    : pagamentos.isEmpty && _selectedDate == null
                        ? const Center(child: Text('Selecione uma data para ver os pagamentos.'))
                        : pagamentos.isEmpty && _selectedDate != null
                            ? const Center(child: Text('Nenhum pagamento encontrado para a data selecionada.'))
                            : ListView.builder(
                                itemCount: groupedPayments.length,
                                itemBuilder: (context, index) {
                                  String transacaoId = groupedPayments.keys.elementAt(index);
                                  List<Map<String, dynamic>> grupoDePagamentos = groupedPayments[transacaoId]!;
                                  
                                  // Calcula o total e pega a data da transação
                                  double totalTransacao = grupoDePagamentos.fold(0, (sum, item) => sum + (item['valor'] as num));
                                  DateTime dataTransacao = DateTime.parse(grupoDePagamentos.first['data_pagamento']);
                                  String meioPagamento = grupoDePagamentos.first['meio_pagamento'];
                                  
                                  return GestureDetector(
                                    onLongPress: () => _showRevertPaymentDialog(transacaoId),
                                    child: Card(
                                      child: ExpansionTile(
                                        title: Text('Total: R\$${totalTransacao.toStringAsFixed(2)}'),
                                        subtitle: Text(
                                          'Data: ${dataTransacao.day}/${dataTransacao.month}/${dataTransacao.year} | Meio: $meioPagamento'
                                        ),
                                        children: grupoDePagamentos.map((pagamento) {
                                          return ListTile(
                                            title: Text(pagamento['descricao']),
                                            subtitle: Text('Valor: R\$${(pagamento['valor'] as num).toStringAsFixed(2)}'),
                                          );
                                        }).toList(),
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
import 'package:flutter/material.dart';
import 'database_helper.dart';
import 'pagamentos_page.dart';
import 'package:uuid/uuid.dart';

enum MeioPagamento { dinheiro, credito, debito, pix }

class ContaPagarPage extends StatefulWidget {
  const ContaPagarPage({super.key});

  @override
  _ContaPagarPageState createState() => _ContaPagarPageState();
}

class _ContaPagarPageState extends State<ContaPagarPage> {
  final dbHelper = DatabaseHelper();
  List<Map<String, dynamic>> contas = [];
  bool isLoading = true;
  String? errorMessage;
  
  bool isSelectionMode = false;
  List<int> selectedContasIds = [];

  final TextEditingController _descricaoController = TextEditingController();
  final TextEditingController _valorController = TextEditingController();
  DateTime? _dataVencimento;

  DateTime? _startDate;
  DateTime? _endDate;
  String _filterStatus = 'em_aberto';

  @override
  void initState() {
    super.initState();
    _fetchContas();
  }

  @override
  void dispose() {
    _descricaoController.dispose();
    _valorController.dispose();
    super.dispose();
  }

  void _resetFilters() {
    _startDate = null;
    _endDate = null;
    _filterStatus = 'em_aberto';
    isSelectionMode = false;
    selectedContasIds.clear();
  }

  Future<void> _fetchContas({DateTime? startDate, DateTime? endDate, String? status}) async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    if (startDate == null && endDate == null && status == null) {
      _resetFilters();
    }

    int? statusValue;
    if (status == 'em_aberto') {
      statusValue = 0;
    } else if (status == 'pagas') {
      statusValue = 1;
    }

    try {
      List<Map<String, dynamic>> listaContas = await dbHelper.getContasByFilter(
        startDate: startDate,
        endDate: endDate,
        status: statusValue,
      );

      List<Map<String, dynamic>> vencidas = [];
      List<Map<String, dynamic>> naoVencidas = [];
      List<Map<String, dynamic>> pagas = [];
      
      final today = DateTime.now();
      final todayZeroTime = DateTime(today.year, today.month, today.day);

      for (var conta in listaContas) {
        if (conta['paga'] == 1) {
          pagas.add(conta);
        } else {
          final dataVencimento = DateTime.parse(conta['data']);
          final dataZeroTime = DateTime(dataVencimento.year, dataVencimento.month, dataVencimento.day);
          
          if (dataZeroTime.isBefore(todayZeroTime)) {
            vencidas.add(conta);
          } else {
            naoVencidas.add(conta);
          }
        }
      }

      vencidas.sort((a, b) => DateTime.parse(a['data']).compareTo(DateTime.parse(b['data'])));
      naoVencidas.sort((a, b) => DateTime.parse(a['data']).compareTo(DateTime.parse(b['data'])));
      pagas.sort((a, b) => DateTime.parse(a['data']).compareTo(DateTime.parse(b['data'])));


      if (status == 'em_aberto' || status == null) {
        contas = [...vencidas, ...naoVencidas];
      } else if (status == 'pagas') {
        contas = pagas;
      } else {
        contas = [...vencidas, ...naoVencidas, ...pagas];
      }
    } catch (e) {
      print('Erro ao carregar ou ordenar as contas: $e');
      setState(() {
        errorMessage = 'Erro ao carregar as contas. Por favor, reinicie o aplicativo.';
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _addConta(String descricao, double valor, DateTime dataVencimento) async {
    Map<String, dynamic> novaConta = {
      'descricao': descricao,
      'valor': valor,
      'data': dataVencimento.toIso8601String(),
      'paga': 0,
    };
    await dbHelper.insertConta(novaConta);
    _fetchContas(startDate: _startDate, endDate: _endDate, status: _filterStatus);
  }

  Future<void> _updateConta(int id, String descricao, double valor, DateTime dataVencimento) async {
    Map<String, dynamic> contaAtualizada = {
      'id': id,
      'descricao': descricao,
      'valor': valor,
      'data': dataVencimento.toIso8601String(),
    };
    await dbHelper.updateConta(contaAtualizada);
    _fetchContas(startDate: _startDate, endDate: _endDate, status: _filterStatus);
  }

  Future<void> _marcarComoPaga(DateTime data, MeioPagamento meio) async {
    final transacaoId = Uuid().v4();
    
    for (int id in selectedContasIds) {
      await dbHelper.updateConta({
        'id': id,
        'paga': 1,
      });
      await dbHelper.insertPagamento({
        'conta_id': id,
        'transacao_id': transacaoId,
        'data_pagamento': data.toIso8601String(),
        'meio_pagamento': meio.toString().split('.').last,
      });
    }
    setState(() {
      isSelectionMode = false;
      selectedContasIds.clear();
    });
    _fetchContas(startDate: _startDate, endDate: _endDate, status: _filterStatus);
  }

  void _showAddContaDialog() {
    _descricaoController.clear();
    _valorController.clear();
    _dataVencimento = null;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Adicionar Nova Conta"),
          content: StatefulBuilder(
            builder: (BuildContext context, StateSetter setStateInterno) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TextField(
                    controller: _descricaoController,
                    decoration: const InputDecoration(labelText: "Descrição"),
                  ),
                  TextField(
                    controller: _valorController,
                    decoration: const InputDecoration(labelText: "Valor"),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _dataVencimento == null
                              ? "Selecione a data de vencimento"
                              : "Vencimento: ${_dataVencimento!.day}/${_dataVencimento!.month}/${_dataVencimento!.year}",
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.calendar_today),
                        onPressed: () async {
                          final dataSelecionada = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030),
                          );
                          if (dataSelecionada != null) {
                            setStateInterno(() {
                              _dataVencimento = dataSelecionada;
                            });
                          }
                        },
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          actions: <Widget>[
            TextButton(
              child: const Text("Cancelar"),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text("Salvar"),
              onPressed: () {
                if (_descricaoController.text.isNotEmpty &&
                    _valorController.text.isNotEmpty &&
                    _dataVencimento != null) {
                  _addConta(
                    _descricaoController.text,
                    double.parse(_valorController.text),
                    _dataVencimento!,
                  );
                  Navigator.of(context).pop();
                }
              },
            ),
          ],
        );
      },
    );
  }

  void _showEditContaDialog(Map<String, dynamic> conta) {
    _descricaoController.text = conta['descricao'];
    _valorController.text = conta['valor'].toString();
    _dataVencimento = DateTime.parse(conta['data']);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Editar Conta"),
          content: StatefulBuilder(
            builder: (BuildContext context, StateSetter setStateInterno) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TextField(
                    controller: _descricaoController,
                    decoration: const InputDecoration(labelText: "Descrição"),
                  ),
                  TextField(
                    controller: _valorController,
                    decoration: const InputDecoration(labelText: "Valor"),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          "Vencimento: ${_dataVencimento!.day}/${_dataVencimento!.month}/${_dataVencimento!.year}",
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.calendar_today),
                        onPressed: () async {
                          final dataSelecionada = await showDatePicker(
                            context: context,
                            initialDate: _dataVencimento!,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030),
                          );
                          if (dataSelecionada != null) {
                            setStateInterno(() {
                              _dataVencimento = dataSelecionada;
                            });
                          }
                        },
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          actions: <Widget>[
            TextButton(
              child: const Text("Cancelar"),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text("Salvar"),
              onPressed: () {
                if (_descricaoController.text.isNotEmpty &&
                    _valorController.text.isNotEmpty &&
                    _dataVencimento != null) {
                  _updateConta(
                    conta['id'],
                    _descricaoController.text,
                    double.parse(_valorController.text),
                    _dataVencimento!,
                  );
                  Navigator.of(context).pop();
                }
              },
            ),
          ],
        );
      },
    );
  }

  void _showPaymentDialog() {
    DateTime? dataPagamento = DateTime.now();
    MeioPagamento? meioPagamento = MeioPagamento.dinheiro;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Registrar Pagamento'),
          content: StatefulBuilder(
            builder: (BuildContext context, StateSetter setStateInterno) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Data: ${dataPagamento?.day}/${dataPagamento?.month}/${dataPagamento?.year}',
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.calendar_today),
                        onPressed: () async {
                          final dataSelecionada = await showDatePicker(
                            context: context,
                            initialDate: dataPagamento ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030),
                          );
                          if (dataSelecionada != null) {
                            setStateInterno(() {
                              dataPagamento = dataSelecionada;
                            });
                          }
                        },
                      ),
                    ],
                  ),
                  DropdownButton<MeioPagamento>(
                    value: meioPagamento,
                    onChanged: (MeioPagamento? newValue) {
                      setStateInterno(() {
                        meioPagamento = newValue;
                      });
                    },
                    items: MeioPagamento.values.map((MeioPagamento value) {
                      return DropdownMenuItem<MeioPagamento>(
                        value: value,
                        child: Text(value.toString().split('.').last),
                      );
                    }).toList(),
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () async {
                if (dataPagamento == null || meioPagamento == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Por favor, selecione a data e o meio de pagamento.')),
                  );
                  return;
                }
                
                try {
                  await _marcarComoPaga(dataPagamento!, meioPagamento!);
                  Navigator.of(context).pop();
                } catch (e) {
                  print('Erro ao salvar o pagamento: $e');
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Erro ao salvar. Verifique o console.')),
                  );
                }
              },
              child: const Text('Salvar'),
            ),
          ],
        );
      },
    );
  }

  void _toggleSelection(int id) {
    setState(() {
      if (selectedContasIds.contains(id)) {
        selectedContasIds.remove(id);
        if (selectedContasIds.isEmpty) {
          isSelectionMode = false;
        }
      } else {
        selectedContasIds.add(id);
      }
    });
  }

  double _calculateTotal() {
    return contas.fold(0, (sum, item) => sum + item['valor']);
  }

  double _calculateDailyTotal() {
    final today = DateTime.now();
    return contas
        .where((conta) {
          final data = DateTime.parse(conta['data']);
          return conta['paga'] == 0 && data.year == today.year && data.month == today.month && data.day == today.day;
        })
        .fold(0, (sum, item) => sum + item['valor']);
  }

  double _calculateOverdueTotal() {
    final today = DateTime.now();
    return contas
        .where((conta) {
          final data = DateTime.parse(conta['data']);
          final todayZeroTime = DateTime(today.year, today.month, today.day);
          final dataZeroTime = DateTime(data.year, data.month, data.day);
          return conta['paga'] == 0 && dataZeroTime.isBefore(todayZeroTime);
        })
        .fold(0, (sum, item) => sum + item['valor']);
  }

  double _calculatePaidTotal() {
    return contas
        .where((conta) => conta['paga'] == 1)
        .fold(0, (sum, item) => sum + item['valor']);
  }

  double _calculateSelectedTotal() {
    double total = 0;
    for (var id in selectedContasIds) {
      final conta = contas.firstWhere((element) => element['id'] == id);
      total += conta['valor'];
    }
    return total;
  }
  
  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        DateTime? tempStartDate = _startDate;
        DateTime? tempEndDate = _endDate;
        String tempFilterStatus = _filterStatus;

        return AlertDialog(
          title: const Text('Filtrar Contas'),
          content: StatefulBuilder(
            builder: (context, StateSetter setStateInterno) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: Text(tempStartDate == null
                        ? 'Data Início: Não selecionada'
                        : 'Data Início: ${tempStartDate!.day}/${tempStartDate!.month}/${tempStartDate!.year}'),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: tempStartDate ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                      );
                      if (picked != null) {
                        setStateInterno(() {
                          tempStartDate = picked;
                        });
                      }
                    },
                  ),
                  ListTile(
                    title: Text(tempEndDate == null
                        ? 'Data Fim: Não selecionada'
                        : 'Data Fim: ${tempEndDate!.day}/${tempEndDate!.month}/${tempEndDate!.year}'),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: tempEndDate ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                      );
                      if (picked != null) {
                        setStateInterno(() {
                          tempEndDate = picked;
                        });
                      }
                    },
                  ),
                  DropdownButtonFormField<String>(
                    value: tempFilterStatus,
                    items: const [
                      DropdownMenuItem(
                        value: 'em_aberto',
                        child: Text('Em Aberto'),
                      ),
                      DropdownMenuItem(
                        value: 'pagas',
                        child: Text('Pagas'),
                      ),
                      DropdownMenuItem(
                        value: 'todas',
                        child: Text('Todas'),
                      ),
                    ],
                    onChanged: (value) {
                      setStateInterno(() {
                        tempFilterStatus = value!;
                      });
                    },
                    decoration: const InputDecoration(labelText: 'Status'),
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                _resetFilters();
                _fetchContas();
                Navigator.of(context).pop();
              },
              child: const Text('Limpar Filtros'),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _startDate = tempStartDate;
                  _endDate = tempEndDate;
                  _filterStatus = tempFilterStatus;
                });
                _fetchContas(startDate: _startDate, endDate: _endDate, status: _filterStatus);
                Navigator.of(context).pop();
              },
              child: const Text('Aplicar'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: isSelectionMode
            ? Text('${selectedContasIds.length} selecionado(s)')
            : const Text('Contas a Pagar'),
        centerTitle: true,
        actions: isSelectionMode
            ? <Widget>[
                IconButton(
                  icon: const Icon(Icons.check_circle_outline),
                  onPressed: _showPaymentDialog,
                ),
                IconButton(
                  icon: const Icon(Icons.cancel),
                  onPressed: () {
                    setState(() {
                      isSelectionMode = false;
                      selectedContasIds.clear();
                    });
                  },
                ),
              ]
            : <Widget>[
                PopupMenuButton<String>(
                  onSelected: (value) async {
                    if (value == 'ver_pagamentos') {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const PagamentosPage()),
                      );
                      _fetchContas();
                    } else if (value == 'filtrar') {
                      _showFilterDialog();
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'filtrar',
                      child: Text('Filtrar Contas'),
                    ),
                    const PopupMenuItem(
                      value: 'ver_pagamentos',
                      child: Text('Ver Pagamentos'),
                    ),
                  ],
                ),
              ],
      ),
      body: Column(
        children: [
          if (_startDate != null || _endDate != null || _filterStatus != 'em_aberto')
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                'Filtro: ${_startDate != null ? '${_startDate!.day}/${_startDate!.month}/${_startDate!.year}' : ''} - ${_endDate != null ? '${_endDate!.day}/${_endDate!.month}/${_endDate!.year}' : ''} | Status: ${_filterStatus.toUpperCase()}',
                style: const TextStyle(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : errorMessage != null
                    ? Center(child: Text(errorMessage!))
                    : contas.isEmpty
                        ? const Center(child: Text('Nenhuma conta encontrada.'))
                        : ListView.builder(
                            itemCount: contas.length,
                            itemBuilder: (context, index) {
                              final conta = contas[index];
                              final isPaga = conta['paga'] == 1;
                              final dataVencimento = DateTime.parse(conta['data']);
                              
                              final today = DateTime.now();
                              final todayZeroTime = DateTime(today.year, today.month, today.day);
                              final dataZeroTime = DateTime(dataVencimento.year, dataVencimento.month, dataVencimento.day);
                              final vencida = dataZeroTime.isBefore(todayZeroTime);
                              
                              final isSelected = selectedContasIds.contains(conta['id']);
                              
                              Color? corFundo = isSelected
                                ? Colors.blue[100]
                                : isPaga ? Colors.grey[300] : (vencida ? Colors.red[100] : null);

                              return GestureDetector(
                                onDoubleTap: () {
                                  if (!isPaga) _showEditContaDialog(conta);
                                },
                                onLongPress: () {
                                  if (!isPaga) {
                                    setState(() {
                                      isSelectionMode = true;
                                      _toggleSelection(conta['id']);
                                    });
                                  }
                                },
                                onTap: () {
                                  if (isSelectionMode && !isPaga) {
                                    _toggleSelection(conta['id']);
                                  }
                                },
                                child: ListTile(
                                  tileColor: corFundo,
                                  title: Text(
                                    conta['descricao'],
                                    style: TextStyle(
                                      decoration: isPaga ? TextDecoration.lineThrough : null,
                                      color: isPaga ? Colors.grey[700] : Colors.black,
                                      fontStyle: isPaga ? FontStyle.italic : null,
                                    ),
                                  ),
                                  subtitle: Text(
                                      'Valor: R\$${conta['valor'].toStringAsFixed(2)} - Vencimento: ${dataVencimento.day}/${dataVencimento.month}/${dataVencimento.year}'),
                                  leading: isSelectionMode
                                      ? Checkbox(
                                          value: isSelected,
                                          onChanged: (bool? value) {
                                            if (!isPaga) _toggleSelection(conta['id']);
                                          },
                                        )
                                      : null,
                                  trailing: Icon(
                                    isPaga ? Icons.check_circle : (vencida ? Icons.error : Icons.radio_button_unchecked),
                                    color: isPaga ? Colors.green : (vencida ? Colors.red : Colors.grey),
                                  ),
                                ),
                              );
                            },
                          ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Total de Contas: R\$${_calculateTotal().toStringAsFixed(2)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Text('Vencendo hoje: R\$${_calculateDailyTotal().toStringAsFixed(2)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Text('Total de Vencidas: R\$${_calculateOverdueTotal().toStringAsFixed(2)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Text('Total Pago: R\$${_calculatePaidTotal().toStringAsFixed(2)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                if (isSelectionMode)
                  Text('Total Selecionado: R\$${_calculateSelectedTotal().toStringAsFixed(2)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: !isSelectionMode
          ? FloatingActionButton(
              onPressed: _showAddContaDialog,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}
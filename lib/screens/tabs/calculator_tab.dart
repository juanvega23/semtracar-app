import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Añade este import
import '../../utils/shipping_calculator.dart';

class CalculatorTab extends StatefulWidget {
  @override
  _CalculatorTabState createState() => _CalculatorTabState();
}

class _CalculatorTabState extends State<CalculatorTab> {
  final _weightController = TextEditingController();
  ShippingMethod _selectedMethod = ShippingMethod.air;
  PackageCategory _selectedCategory = PackageCategory.clothes;
  double _totalPrice = 0.0;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _weightController.addListener(_validateWeightInput);
  }

  @override
  void dispose() {
    _weightController.removeListener(_validateWeightInput);
    _weightController.dispose();
    super.dispose();
  }

  void _validateWeightInput() {
    final text = _weightController.text;
    if (text.isNotEmpty) {
      final weight = double.tryParse(text.replaceAll(',', '.')) ?? 0;
      if (weight > 1000) {
        _weightController.text = '1000';
        _weightController.selection = TextSelection.fromPosition(
          TextPosition(offset: _weightController.text.length),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.fromARGB(0, 0, 0, 0),
              Color.fromARGB(0, 0, 0, 0),
              Color.fromARGB(0, 0, 0, 0),
            ],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                  left: 20,
                  right: 20,
                  top: 10,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Tarjeta de entrada
                      Card(
                        color: Colors.white,
                        elevation: 8,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Campo de peso (modificado)
                                TextFormField(
                                  controller: _weightController,
                                  keyboardType: TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                      RegExp(r'^\d*\.?\d{0,2}'),
                                    ),
                                    LengthLimitingTextInputFormatter(7),
                                  ],
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Ingrese el peso';
                                    }
                                    final weight = double.tryParse(
                                      value.replaceAll(',', '.'),
                                    );
                                    if (weight == null) {
                                      return 'Formato inválido (ej: 5.25)';
                                    }
                                    if (weight <= 0) {
                                      return 'El peso debe ser positivo';
                                    }
                                    if (weight > 1000) {
                                      return 'Máximo permitido: 1000 lbs';
                                    }
                                    return null;
                                  },
                                  decoration: InputDecoration(
                                    labelText: 'Peso (libras)',
                                    prefixIcon: Icon(
                                      Icons.scale,
                                      color: Color(0xFFFA4B0C),
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    suffixText: 'lbs',
                                  ),
                                  onChanged: (value) {
                                    if (value.isNotEmpty) {
                                      final num =
                                          double.tryParse(
                                            value.replaceAll(',', '.'),
                                          ) ??
                                          0;
                                      if (num > 1000) {
                                        _weightController.text = '1000';
                                        _weightController.selection =
                                            TextSelection.fromPosition(
                                              TextPosition(
                                                offset:
                                                    _weightController
                                                        .text
                                                        .length,
                                              ),
                                            );
                                      }
                                    }
                                  },
                                ),
                                SizedBox(height: 15),
                                // Resto del código permanece igual...
                                DropdownButtonFormField<ShippingMethod>(
                                  value: _selectedMethod,
                                  items:
                                      ShippingMethod.values.map((method) {
                                        return DropdownMenuItem(
                                          value: method,
                                          child: Text(
                                            method == ShippingMethod.air
                                                ? 'Por Avión'
                                                : 'Por Mar',
                                            style: TextStyle(
                                              color: Colors.black87,
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                  onChanged:
                                      (value) => setState(
                                        () => _selectedMethod = value!,
                                      ),
                                  decoration: InputDecoration(
                                    labelText: 'Método de Envío',
                                    prefixIcon: Icon(
                                      Icons.directions,
                                      color: Color(0xFFFA4B0C),
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                                SizedBox(height: 15),
                                DropdownButtonFormField<PackageCategory>(
                                  value: _selectedCategory,
                                  items:
                                      PackageCategory.values.map((category) {
                                        return DropdownMenuItem(
                                          value: category,
                                          child: Text(
                                            _getCategoryName(category),
                                            style: TextStyle(
                                              color: Colors.black87,
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                  onChanged:
                                      (value) => setState(
                                        () => _selectedCategory = value!,
                                      ),
                                  decoration: InputDecoration(
                                    labelText: 'Categoría',
                                    prefixIcon: Icon(
                                      Icons.category,
                                      color: Color(0xFFFA4B0C),
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                                SizedBox(height: 20),
                                ElevatedButton(
                                  onPressed: _calculatePrice,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Color(0xFF12327F),
                                    minimumSize: Size(double.infinity, 50),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: Text(
                                    'CALCULAR PRECIO',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 20),
                      Card(
                        color: Color(0xFFFA4B0C).withOpacity(0.9),
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Costo Total:',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 10),
                              Text(
                                '\$${_totalPrice.toStringAsFixed(2)}',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  String _getCategoryName(PackageCategory category) {
    switch (category) {
      case PackageCategory.clothes:
        return 'Ropa';
      case PackageCategory.jewelry:
        return 'Joyería';
      case PackageCategory.electronics:
        return 'Electrónica/Tecnología';
    }
  }

  void _calculatePrice() {
    if (_formKey.currentState!.validate()) {
      final weight = double.parse(_weightController.text.replaceAll(',', '.'));

      setState(() {
        _totalPrice = ShippingCalculator.calculatePrice(
          weightLbs: weight,
          method: _selectedMethod,
          category: _selectedCategory,
        );
      });

      FocusScope.of(context).unfocus();
    }
  }
}

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/app_localizations.dart';

class NutritionTrackerPage extends StatefulWidget {
  const NutritionTrackerPage({super.key, required this.language});
  final String language;

  @override
  State<NutritionTrackerPage> createState() => _NutritionTrackerPageState();
}

class _NutritionTrackerPageState extends State<NutritionTrackerPage> {
  String _t(String v) => AppLocalizations(widget.language).text(v);

  int _dailyCalorieGoal = 2000;
  int _totalCalories = 0;
  double _totalProtein = 0;
  double _totalCarbs = 0;
  double _totalFat = 0;
  List<Map<String, dynamic>> _todayMeals = [];
  String _todayKey = '';

  // Predefined food database
  static const List<Map<String, dynamic>> _foodDatabase = [
    // Fruits
    {'name': 'Apple', 'calories': 95, 'protein': 0.5, 'carbs': 25, 'fat': 0.3, 'icon': '🍎', 'category': 'Fruit'},
    {'name': 'Banana', 'calories': 105, 'protein': 1.3, 'carbs': 27, 'fat': 0.4, 'icon': '🍌', 'category': 'Fruit'},
    {'name': 'Orange', 'calories': 62, 'protein': 1.2, 'carbs': 15, 'fat': 0.2, 'icon': '🍊', 'category': 'Fruit'},
    {'name': 'Mango', 'calories': 99, 'protein': 1.4, 'carbs': 25, 'fat': 0.6, 'icon': '🥭', 'category': 'Fruit'},
    {'name': 'Grapes', 'calories': 62, 'protein': 0.6, 'carbs': 16, 'fat': 0.3, 'icon': '🍇', 'category': 'Fruit'},
    {'name': 'Watermelon', 'calories': 46, 'protein': 0.9, 'carbs': 12, 'fat': 0.2, 'icon': '🍉', 'category': 'Fruit'},
    {'name': 'Pineapple', 'calories': 82, 'protein': 0.9, 'carbs': 22, 'fat': 0.2, 'icon': '🍍', 'category': 'Fruit'},
    {'name': 'Strawberry', 'calories': 49, 'protein': 1.0, 'carbs': 12, 'fat': 0.5, 'icon': '🍓', 'category': 'Fruit'},

    // Vegetables
    {'name': 'Rice (1 cup)', 'calories': 206, 'protein': 4.3, 'carbs': 45, 'fat': 0.4, 'icon': '🍚', 'category': 'Grain'},
    {'name': 'Roti/Chapati', 'calories': 120, 'protein': 3.6, 'carbs': 22, 'fat': 2.0, 'icon': '🫓', 'category': 'Grain'},
    {'name': 'Bread (2 slices)', 'calories': 150, 'protein': 5.0, 'carbs': 28, 'fat': 2.0, 'icon': '🍞', 'category': 'Grain'},
    {'name': 'Noodles (1 cup)', 'calories': 220, 'protein': 5.0, 'carbs': 38, 'fat': 5.0, 'icon': '🍜', 'category': 'Grain'},
    {'name': 'Idli (2 pcs)', 'calories': 140, 'protein': 4.0, 'carbs': 28, 'fat': 1.0, 'icon': '🫓', 'category': 'Grain'},
    {'name': 'Dosa (1 pc)', 'calories': 130, 'protein': 3.0, 'carbs': 22, 'fat': 4.0, 'icon': '🫓', 'category': 'Grain'},

    // Proteins
    {'name': 'Egg (1)', 'calories': 78, 'protein': 6.3, 'carbs': 0.6, 'fat': 5.3, 'icon': '🥚', 'category': 'Protein'},
    {'name': 'Chicken Breast', 'calories': 165, 'protein': 31, 'carbs': 0, 'fat': 3.6, 'icon': '🍗', 'category': 'Protein'},
    {'name': 'Fish (salmon)', 'calories': 208, 'protein': 20, 'carbs': 0, 'fat': 13, 'icon': '🐟', 'category': 'Protein'},
    {'name': 'Paneer (100g)', 'calories': 265, 'protein': 18, 'carbs': 4, 'fat': 20, 'icon': '🧀', 'category': 'Protein'},
    {'name': 'Tofu (100g)', 'calories': 76, 'protein': 8, 'carbs': 2, 'fat': 4.8, 'icon': '🧊', 'category': 'Protein'},
    {'name': 'Lentils (Dal)', 'calories': 116, 'protein': 9, 'carbs': 20, 'fat': 0.4, 'icon': '🫘', 'category': 'Protein'},

    // Dairy
    {'name': 'Milk (1 glass)', 'calories': 150, 'protein': 8, 'carbs': 12, 'fat': 8, 'icon': '🥛', 'category': 'Dairy'},
    {'name': 'Curd/Yogurt', 'calories': 100, 'protein': 6, 'carbs': 12, 'fat': 3.5, 'icon': '🥣', 'category': 'Dairy'},
    {'name': 'Cheese (slice)', 'calories': 113, 'protein': 7, 'carbs': 0.4, 'fat': 9, 'icon': '🧀', 'category': 'Dairy'},

    // Beverages
    {'name': 'Tea (with sugar)', 'calories': 40, 'protein': 0.5, 'carbs': 10, 'fat': 0.2, 'icon': '🍵', 'category': 'Beverage'},
    {'name': 'Coffee (with milk)', 'calories': 50, 'protein': 2, 'carbs': 6, 'fat': 2, 'icon': '☕', 'category': 'Beverage'},
    {'name': 'Orange Juice', 'calories': 112, 'protein': 1.7, 'carbs': 26, 'fat': 0.5, 'icon': '🧃', 'category': 'Beverage'},

    // Snacks
    {'name': 'Samosa (1)', 'calories': 250, 'protein': 4, 'carbs': 28, 'fat': 14, 'icon': '🥟', 'category': 'Snack'},
    {'name': 'Biscuit (2)', 'calories': 80, 'protein': 1.5, 'carbs': 12, 'fat': 3, 'icon': '🍪', 'category': 'Snack'},
    {'name': 'Banana Chips', 'calories': 180, 'protein': 1, 'carbs': 28, 'fat': 9, 'icon': '🍘', 'category': 'Snack'},
    {'name': 'Peanuts (handful)', 'calories': 170, 'protein': 7, 'carbs': 6, 'fat': 14, 'icon': '🥜', 'category': 'Snack'},

    // Meals
    {'name': 'Thali (South Indian)', 'calories': 450, 'protein': 15, 'carbs': 65, 'fat': 12, 'icon': '🍛', 'category': 'Meal'},
    {'name': 'Thali (North Indian)', 'calories': 500, 'protein': 18, 'carbs': 60, 'fat': 18, 'icon': '🍛', 'category': 'Meal'},
    {'name': 'Biryani', 'calories': 350, 'protein': 15, 'carbs': 45, 'fat': 12, 'icon': '🍛', 'category': 'Meal'},
    {'name': 'Parotta with Curry', 'calories': 400, 'protein': 10, 'carbs': 50, 'fat': 18, 'icon': '🫓', 'category': 'Meal'},
    {'name': 'Chapati + Sabzi', 'calories': 280, 'protein': 8, 'carbs': 40, 'fat': 8, 'icon': '🍛', 'category': 'Meal'},
    {'name': 'Pizza (2 slices)', 'calories': 540, 'protein': 20, 'carbs': 60, 'fat': 24, 'icon': '🍕', 'category': 'Meal'},
    {'name': 'Burger', 'calories': 350, 'protein': 18, 'carbs': 35, 'fat': 15, 'icon': '🍔', 'category': 'Meal'},
    {'name': 'Sandwich', 'calories': 250, 'protein': 12, 'carbs': 30, 'fat': 10, 'icon': '🥪', 'category': 'Meal'},

    // Sweets
    {'name': 'Gulab Jamun (2)', 'calories': 175, 'protein': 2, 'carbs': 30, 'fat': 6, 'icon': '🍩', 'category': 'Sweet'},
    {'name': 'Jalebi (2 pcs)', 'calories': 150, 'protein': 1, 'carbs': 28, 'fat': 4, 'icon': '🍩', 'category': 'Sweet'},
    {'name': 'Ice Cream (1 scoop)', 'calories': 140, 'protein': 2, 'carbs': 18, 'fat': 7, 'icon': '🍦', 'category': 'Sweet'},
  ];

  @override
  void initState() {
    super.initState();
    _todayKey = _getTodayKey();
    _loadData();
  }

  String _getTodayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    _dailyCalorieGoal = prefs.getInt('nutrition_goal') ?? 2000;
    final saved = prefs.getStringList('meals_$_todayKey') ?? [];
    _todayMeals = saved.map((s) => Map<String, dynamic>.from(jsonDecode(s))).toList();
    _calculateTotals();
    if (mounted) setState(() {});
  }

  void _calculateTotals() {
    _totalCalories = 0;
    _totalProtein = 0;
    _totalCarbs = 0;
    _totalFat = 0;
    for (final meal in _todayMeals) {
      _totalCalories += (meal['calories'] as int?) ?? 0;
      _totalProtein += (meal['protein'] as double?) ?? 0;
      _totalCarbs += (meal['carbs'] as double?) ?? 0;
      _totalFat += (meal['fat'] as double?) ?? 0;
    }
  }

  Future<void> _addFood(Map<String, dynamic> food) async {
    final mealType = await _showMealTypeDialog();
    if (mealType == null) return;

    final entry = {
      'name': food['name'],
      'calories': food['calories'],
      'protein': food['protein'],
      'carbs': food['carbs'],
      'fat': food['fat'],
      'icon': food['icon'],
      'meal': mealType,
      'time': TimeOfDay.now().format(context),
    };

    setState(() => _todayMeals.add(entry));
    _calculateTotals();

    final prefs = await SharedPreferences.getInstance();
    final list = _todayMeals.map((m) => jsonEncode(m)).toList();
    await prefs.setStringList('meals_$_todayKey', list);
  }

  Future<String?> _showMealTypeDialog() async {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_t('Select meal type')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _mealOption(ctx, '🌅 ${_t('Breakfast')}', 'Breakfast'),
            _mealOption(ctx, '☀️ ${_t('Lunch')}', 'Lunch'),
            _mealOption(ctx, '🌙 ${_t('Dinner')}', 'Dinner'),
            _mealOption(ctx, '🍿 ${_t('Snacks')}', 'Snacks'),
          ],
        ),
      ),
    );
  }

  Widget _mealOption(BuildContext ctx, String label, String value) {
    return ListTile(
      title: Text(label),
      onTap: () => Navigator.pop(ctx, value),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }

  Future<void> _removeMeal(int index) async {
    setState(() => _todayMeals.removeAt(index));
    _calculateTotals();
    final prefs = await SharedPreferences.getInstance();
    final list = _todayMeals.map((m) => jsonEncode(m)).toList();
    await prefs.setStringList('meals_$_todayKey', list);
  }

  void _showGoalDialog() {
    int tempGoal = _dailyCalorieGoal;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(_t('Set Daily Calorie Goal')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$tempGoal kcal', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF2E7D32))),
              Slider(
                value: tempGoal.toDouble(),
                min: 1000,
                max: 5000,
                divisions: 40,
                label: '$tempGoal',
                activeColor: const Color(0xFF2E7D32),
                onChanged: (v) => setDialogState(() => tempGoal = v.toInt()),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('1000', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                  Text('5000', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [1500, 2000, 2500, 3000, 3500].map((preset) {
                  return ActionChip(
                    label: Text('$preset', style: const TextStyle(fontSize: 12)),
                    backgroundColor: tempGoal == preset ? const Color(0xFF2E7D32).withValues(alpha: 0.2) : null,
                    onPressed: () => setDialogState(() => tempGoal = preset),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_t('Cancel'))),
            ElevatedButton(
              onPressed: () async {
                setState(() => _dailyCalorieGoal = tempGoal);
                final prefs = await SharedPreferences.getInstance();
                await prefs.setInt('nutrition_goal', _dailyCalorieGoal);
                if (mounted) Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
              child: Text(_t('Save'), style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showFoodPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        String searchQuery = '';
        String selectedCategory = 'All';
        final categories = ['All', 'Fruit', 'Grain', 'Protein', 'Dairy', 'Beverage', 'Snack', 'Meal', 'Sweet'];

        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final filtered = _foodDatabase.where((f) {
              final matchesSearch = searchQuery.isEmpty || f['name'].toString().toLowerCase().contains(searchQuery.toLowerCase());
              final matchesCategory = selectedCategory == 'All' || f['category'] == selectedCategory;
              return matchesSearch && matchesCategory;
            }).toList();

            return DraggableScrollableSheet(
              initialChildSize: 0.85,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              expand: false,
              builder: (_, scrollController) => Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Text(_t('Add Food'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        TextField(
                          onChanged: (v) => setSheetState(() => searchQuery = v),
                          decoration: InputDecoration(
                            hintText: _t('Search food...'),
                            prefixIcon: const Icon(Icons.search),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 36,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: categories.length,
                            itemBuilder: (_, i) => Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                label: Text(categories[i], style: const TextStyle(fontSize: 11)),
                                selected: selectedCategory == categories[i],
                                onSelected: (_) => setSheetState(() => selectedCategory = categories[i]),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final food = filtered[i];
                        return ListTile(
                          leading: Text(food['icon'], style: const TextStyle(fontSize: 28)),
                          title: Text(food['name'], style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('${food['calories']} kcal • P:${food['protein']}g C:${food['carbs']}g F:${food['fat']}g',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                          trailing: const Icon(Icons.add_circle, color: Color(0xFF2E7D32)),
                          onTap: () {
                            Navigator.pop(ctx);
                            _addFood(food);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final progress = (_totalCalories / _dailyCalorieGoal).clamp(0.0, 1.0);
    final remaining = _dailyCalorieGoal - _totalCalories;
    final goalReached = _totalCalories >= _dailyCalorieGoal;

    return Scaffold(
      appBar: AppBar(
        title: Text(_t('Nutrition Tracker')),
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.flag_rounded),
            onPressed: _showGoalDialog,
            tooltip: _t('Set Goal'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Calorie overview card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF1B3A1B), const Color(0xFF0D260D)]
                    : [const Color(0xFFE8F5E9), const Color(0xFFC8E6C9)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                // Circular progress
                SizedBox(
                  width: 140,
                  height: 140,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 140,
                        height: 140,
                        child: CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 12,
                          backgroundColor: isDark ? Colors.white12 : Colors.white,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            goalReached ? Colors.red : const Color(0xFF2E7D32),
                          ),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$_totalCalories',
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          Text(
                            '/ $_dailyCalorieGoal kcal',
                            style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.black54),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  goalReached ? '🔴 ${_t('Goal exceeded!')}' : '$remaining kcal ${_t('remaining')}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: goalReached ? Colors.red : (isDark ? Colors.white70 : Colors.black54),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Nutrition breakdown
          Row(
            children: [
              _nutrientCard('🔥', _t('Calories'), '$_totalCalories', 'kcal', Colors.orange, isDark),
              _nutrientCard('💪', _t('Protein'), '${_totalProtein.toStringAsFixed(1)}', 'g', Colors.red, isDark),
              _nutrientCard('🌾', _t('Carbs'), '${_totalCarbs.toStringAsFixed(1)}', 'g', Colors.amber, isDark),
              _nutrientCard('🧈', _t('Fat'), '${_totalFat.toStringAsFixed(1)}', 'g', Colors.purple, isDark),
            ],
          ),

          const SizedBox(height: 20),

          // Meals grouped by type
          ..._buildMealGroups(),

          const SizedBox(height: 20),

          // Quick add section
          Text(_t('Quick Add'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _foodDatabase.take(6).map((food) {
              return ActionChip(
                avatar: Text(food['icon']),
                label: Text('${food['name']} (${food['calories']})', style: const TextStyle(fontSize: 11)),
                onPressed: () => _addFood(food),
              );
            }).toList(),
          ),

          const SizedBox(height: 80),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showFoodPicker,
        backgroundColor: const Color(0xFF2E7D32),
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text(_t('Add Food'), style: const TextStyle(color: Colors.white)),
      ),
    );
  }

  Widget _nutrientCard(String emoji, String label, String value, String unit, Color color, bool isDark) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDark ? 0.15 : 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
            Text('$label ($unit)', style: TextStyle(fontSize: 9, color: isDark ? Colors.white60 : Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildMealGroups() {
    final meals = {'Breakfast': <Map<String, dynamic>>[], 'Lunch': <Map<String, dynamic>>[], 'Dinner': <Map<String, dynamic>>[], 'Snacks': <Map<String, dynamic>>[]};
    for (final meal in _todayMeals) {
      final type = meal['meal'] ?? 'Snacks';
      if (meals.containsKey(type)) {
        meals[type]!.add(meal);
      }
    }

    final icons = {'Breakfast': '🌅', 'Lunch': '☀️', 'Dinner': '🌙', 'Snacks': '🍿'};

    return meals.entries.map((entry) {
      if (entry.value.isEmpty) return const SizedBox.shrink();
      final mealCals = entry.value.fold<int>(0, (sum, m) => sum + ((m['calories'] as int?) ?? 0));

      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1F2937) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(icons[entry.key] ?? '', style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Text(entry.key, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('$mealCals kcal', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
            const SizedBox(height: 8),
            ...entry.value.asMap().entries.map((mealEntry) {
              final idx = _todayMeals.indexOf(mealEntry.value);
              final meal = mealEntry.value;
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Text(meal['icon'] ?? '🍽️', style: const TextStyle(fontSize: 22)),
                title: Text(meal['name'], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                subtitle: Text('${meal['calories']} kcal • ${meal['time'] ?? ''}', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                trailing: IconButton(
                  icon: Icon(Icons.close, size: 18, color: Colors.grey.shade400),
                  onPressed: () => _removeMeal(idx),
                ),
              );
            }),
          ],
        ),
      );
    }).toList();
  }
}

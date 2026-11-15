enum ShippingMethod { air, sea }
enum PackageCategory { clothes, jewelry, electronics }

class ShippingCalculator {
  static const Map<ShippingMethod, double> basePrices = {
    ShippingMethod.air: 6.50,
    ShippingMethod.sea: 3.50,
  };

  static const Map<PackageCategory, double> categoryMultipliers = {
    PackageCategory.clothes: 1.0,
    PackageCategory.jewelry: 1.10,
    PackageCategory.electronics: 1.10,
  };

  static double calculatePrice({
    required double weightLbs,
    required ShippingMethod method,
    required PackageCategory category,
  }) {
    final basePrice = basePrices[method]!;
    final multiplier = categoryMultipliers[category]!;
    return (weightLbs * basePrice) * multiplier;
  }
}
// lib/utils/category_utils.dart
import '../models/category_model.dart';
import '../models/wallet_model.dart';

bool areCategoryListsEqual(List<Category> list1, List<Category> list2) {
  if (list1.length != list2.length) return false;
  for (int i = 0; i < list1.length; i++) {
    final a = list1[i];
    final b = list2[i];
    if (a.categoryId != b.categoryId || a.name != b.name || a.type != b.type) {
      return false;
    }
  }
  return true;
}

bool areWalletListsEqual(List<Wallet> list1, List<Wallet> list2) {
  if (list1.length != list2.length) return false;
  for (int i = 0; i < list1.length; i++) {
    final a = list1[i];
    final b = list2[i];
    if (a.walletId != b.walletId ||
        a.walletName != b.walletName ||
        a.type != b.type ||
        a.balance != b.balance ||
        a.isActive != b.isActive) {
      return false;
    }
  }
  return true;
}

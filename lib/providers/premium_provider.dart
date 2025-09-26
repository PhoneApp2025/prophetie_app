import 'package:flutter/foundation.dart';

class PremiumProvider extends ChangeNotifier {
  bool _isPremium = false;
  bool _betaTest = true;

  bool get isPremium => _betaTest || _isPremium;
  bool get betaTest => _betaTest;

  /// Setzt den Premium-Status und benachrichtigt Listener
  void setPremium(bool val) {
    if (_isPremium != val) {
      _isPremium = val;
      notifyListeners();
    }
  }

  void setBetaTest(bool val) {
    if (_betaTest != val) {
      _betaTest = val;
      notifyListeners();
    }
  }
}

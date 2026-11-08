import 'package:flutter_test/flutter_test.dart';
import 'package:sippier/data/account_store.dart';
import 'package:sippier/phone/phone_state.dart';
import 'package:sippier_core/sippier_core.dart';

void main() {
  test('switched-off accounts show as disabled whatever was reported', () {
    const off = AccountEntry(
      id: 'a',
      settings: AccountSettings(user: 'u', domain: 'example.net'),
      enabled: false,
    );
    const state = PhoneState(
      accounts: [off],
      // e.g. a failed de-REGISTER after switching it off
      status: {'a': AccountStatus(RegState.failed, '481')},
    );
    expect(state.statusOf('a').state, RegState.disabled);
  });
}

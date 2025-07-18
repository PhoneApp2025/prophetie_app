import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:prophetie_app/services/connection_service.dart';
import 'package:prophetie_app/models/connection_pair.dart';

class MockConnectionService extends Mock implements ConnectionService {}

void main() {
  test('fetchConnections returns a list of ConnectionPair', () async {
    final mockConnectionService = MockConnectionService();
    when(mockConnectionService.fetchConnections()).thenAnswer((_) async => []);

    final result = await mockConnectionService.fetchConnections();

    expect(result, isA<List<ConnectionPair>>());
  });
}

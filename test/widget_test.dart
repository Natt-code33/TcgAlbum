import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dashboard_personal/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('App loads smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const PokemonAlbumApp());
    await tester.pump(const Duration(milliseconds: 500));

    // Verify that the title / album dropdown appears.
    expect(find.text('Mi Álbum'), findsOneWidget);
  });
}

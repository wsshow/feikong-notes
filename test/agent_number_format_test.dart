import 'package:fknotes/agent/agent_number_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats agent token counts with compact units', () {
    expect(formatAgentTokenCount(0), '0');
    expect(formatAgentTokenCount(999), '999');
    expect(formatAgentTokenCount(1835), '1.84K');
    expect(formatAgentTokenCount(1183422), '1.18M');
    expect(formatAgentTokenCount(1441792), '1.44M');
    expect(formatAgentTokenCount(1200000000), '1.2B');
  });
}

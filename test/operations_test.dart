import 'package:flutter_test/flutter_test.dart';
import 'package:nchemty_mobile/data/cyclos/cyclos_operations_api.dart';
import 'package:nchemty_mobile/features/common/rich_content.dart';

void main() {
  test('operation form reads fields, submit label and confirmation input', () {
    final f = OperationForm.fromJson({
      'id': '10',
      'name': 'MoMo cash out',
      'internalName': 'momoCashout',
      'scope': 'user',
      'requireConfirmationPassword': true,
      'customSubmitLabel': 'Preview',
      'formParameters': [
        {'internalName': 'phoneNumber', 'name': 'Phone number', 'type': 'string', 'required': true},
        {'internalName': 'amount', 'name': 'Amount', 'type': 'decimal', 'required': true},
      ],
      'confirmationPasswordInput': {
        'allowedCredentials': ['password'],
        'passwordType': {'name': 'Transaction code', 'onlyNumeric': true},
      },
    });
    expect(f.def.key, 'momoCashout');
    expect(f.def.requireConfirmationPassword, isTrue);
    expect(f.submitLabel, 'Preview');
    expect(f.fields.first.looksLikePhone, isTrue);
    expect(f.fields.last.type, 'decimal');
    expect(f.confirmation!.label, 'Transaction code');
  });

  test('result with a confirm action keeps its parameters', () {
    final r = OperationResult.fromJson({
      'resultType': 'richText',
      'title': 'Preview',
      'content': '<p>Amount: 10 000</p><p>Fee: 74</p>',
      'actions': [
        {
          'action': {'id': '11', 'name': 'Confirm', 'scope': 'internal'},
          'parameters': {'phoneNumber': '677123456', 'amount': 10000},
          'primary': true,
        }
      ],
    });
    expect(r.actions.single.op.scope, 'internal');
    expect(r.actions.single.parameters['amount'], '10000');
    expect(htmlToText(r.content!), 'Amount: 10 000\nFee: 74');
  });

  test('rich result tables become label/value rows', () {
    final blocks = parseRichContent(
        '<h3>Top-up not started</h3><p>Top-ups are not open for your account yet.</p>'
        '<table><tr><td>Amount to credit</td><td>75 XAF</td></tr>'
        '<tr><td>Service fees</td><td>10 XAF</td></tr></table>'
        '<p>Nothing was charged.</p>');
    expect(blocks.first, isA<RichHeading>());
    expect((blocks.first as RichHeading).text, 'Top-up not started');
    final rows = blocks.whereType<RichRow>().toList();
    expect(rows.map((r) => r.label), ['Amount to credit', 'Service fees']);
    expect(rows.first.value, '75 XAF');
    expect(blocks.last, isA<RichParagraph>());
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:nchemty_mobile/data/locations/locations_api.dart';

// Shape of nchemty.com/find-us cards: name + type, address, services,
// Call / WhatsApp, then Directions (Google Maps query=lat,lng).
const _html = '''
<html><head><style>.card{color:red}</style></head><body>
<p>3 places</p>
<div class="card">
  <h3><strong>Nchemty head office</strong> <span>Branch</span></h3>
  <p>Great Soppo, Buea · Opposite Baptist Church</p>
  <p>Cash in · Cash out · Account opening · Loans</p>
  <a href="tel:+237677000001">Call</a>
  <a href="https://wa.me/237677000001">WhatsApp</a>
  <a href="https://www.google.com/maps/search/?api=1&query=4.15346,9.24871">Directions</a>
</div>
<div class="card">
  <h3><strong>SR Enterprise</strong> <span>Agent</span></h3>
  <p>Sandpit Entrance, Buea · Opposite Congelcam</p>
  <p>Cash in · Cash out</p>
  <a href="tel:+237699000002">Call</a>
  <a href="https://www.google.com/maps/search/?api=1&amp;query=4.1601,9.2432">Directions</a>
</div>
</body></html>
''';

void main() {
  test('find-us page cards become locations', () {
    final l = parseFindUsHtml(_html);
    expect(l.length, 2);
    expect(l[0].name, 'Nchemty head office');
    expect(l[0].type, 'Branch');
    expect(l[0].address, 'Great Soppo, Buea · Opposite Baptist Church');
    expect(l[0].services, ['Cash in', 'Cash out', 'Account opening', 'Loans']);
    expect(l[0].phone, '+237677000001');
    expect(l[0].whatsapp, 'https://wa.me/237677000001');
    expect(l[0].lat, closeTo(4.15346, 1e-6));
    expect(l[1].name, 'SR Enterprise');
    expect(l[1].isAgent, isTrue);
    expect(l[1].whatsapp, isNull);
    expect(l[1].lng, closeTo(9.2432, 1e-6));
  });

  test('json feed', () {
    final p = NchemtyLocation.fromJson({
      'name': 'SR Enterprise', 'type': 'Agent', 'town': 'Buea', 'landmark': 'Opposite Congelcam',
      'services': ['Cash in', 'Cash out'], 'lat': 4.1601, 'lng': '9.2432', 'phone': '+237699000002',
    });
    expect(p.address, 'Buea · Opposite Congelcam');
    expect(p.lng, 9.2432);
    expect(p.services.length, 2);
  });

  test('distance and formatting', () {
    // Two points in Buea about 4.6 km apart.
    final d = distanceMetres(4.15346, 9.24871, 4.1560, 9.2900);
    expect(d, inInclusiveRange(4000, 5000));
    expect(formatDistance(842), '840 m');
    expect(formatDistance(2345), '2.3 km');
    expect(formatDistance(23456), '23 km');
  });
}

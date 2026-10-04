(function(root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  if (root) root.PhLocationSearch = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, function() {
  'use strict';

  const normalize = value => String(value || '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();

  const clean = value => String(value || '').trim().replace(/\s+/g, ' ');

  function variants(query, area = '') {
    const q = clean(query), terms = [q];
    const expanded = q
      .replace(/\bbrgy\.?\s/gi, 'Barangay ')
      .replace(/\bsto\.?\s/gi, 'Santo ')
      .replace(/\bsta\.?\s/gi, 'Santa ')
      .replace(/\bst\.?\s/gi, 'Saint ');
    if (expanded !== q) terms.push(expanded);
    if (/\btown\b/i.test(expanded)) terms.push(expanded.replace(/\btown\b/gi, 'Towne'));
    else if (/\btowne\b/i.test(expanded)) terms.push(expanded.replace(/\btowne\b/gi, 'Town'));
    if (terms.length === 1 && q.split(',')[0].trim().split(/\s+/).length === 2) {
      const parts = q.split(',');
      terms.push([parts[0].replace(/\s+/g, ''), ...parts.slice(1)].join(','));
    }
    return [...new Set(terms)].slice(0, 3).map(term => [term, clean(area)].filter(Boolean).join(', '));
  }

  function kind(r) {
    const category = r.category || r.class, type = r.addresstype || r.type;
    if (category === 'highway' || ['road', 'street'].includes(type)) return 'roads';
    if (category === 'place' || category === 'boundary' || ['city', 'town', 'village', 'suburb', 'neighbourhood', 'quarter', 'hamlet', 'municipality', 'state', 'province', 'region', 'island'].includes(type)) return 'communities';
    return 'places';
  }

  function isNegros(r) {
    if (!r) return false;
    const lat = Number(r.lat), lon = Number(r.lon);
    const inNegrosBounds = Number.isFinite(lat) && Number.isFinite(lon) && lat >= 8.9 && lat <= 11.2 && lon >= 122.3 && lon <= 123.65;
    const text = normalize((r.display_name || '') + ' ' + (r.address?.state || '') + ' ' + (r.address?.county || ''));
    return inNegrosBounds || text.includes('negros occidental') || text.includes('negros oriental') || text.includes('negros island');
  }

  function filter(results, query, type = 'all') {
    const q = normalize(query), compact = q.replaceAll(' ', '');
    const seen = new Set();
    const score = r => {
      const name = normalize(r.name || r.display_name?.split(',')[0]);
      const base = (name === q ? 100 : name.replaceAll(' ', '') === compact ? 90 : name.startsWith(q) ? 60 : 0)
        + (normalize(r.display_name).includes(q) ? 20 : 0)
        + (Number(r.importance) || 0);
      const negrosBoost = isNegros(r) ? 300 : 0;
      const agencyBoost = r.is_agency_site ? 1000 : 0;
      return base + negrosBoost + agencyBoost;
    };

    return (Array.isArray(results) ? results : []).filter(r => {
      if (String(r.address?.country_code).toLowerCase() !== 'ph' || r.lat == null || r.lon == null || String(r.lat).trim() === '' || String(r.lon).trim() === '') return false;
      const lat = Number(r.lat), lon = Number(r.lon);
      if (!Number.isFinite(lat) || !Number.isFinite(lon) || lat < 4.2 || lat > 21.3 || lon < 116.4 || lon > 127) return false;
      if (type !== 'all' && kind(r) !== type) return false;
      const nameNorm = normalize(r.name || r.display_name?.split(',')[0]);
      const key = r.osm_type && r.osm_id ? `${r.osm_type}:${r.osm_id}` : `${nameNorm}:${lat.toFixed(4)}:${lon.toFixed(4)}`;
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    }).sort((a, b) => score(b) - score(a));
  }

  function matchesSite(site, query, status = 'all') {
    return (status === 'all' || (status === 'active') === Boolean(site.active))
      && normalize(query).split(' ').every(word => normalize(`${site.label || ''} ${site.address || ''}`).includes(word));
  }

  // Pre-seeded comprehensive directory of Negros Occidental and Negros Oriental LGUs, barangays, and hubs
  const NEGROS_DIRECTORY = [
    // --- NEGROS OCCIDENTAL CITIES & MUNICIPALITIES ---
    { n: "Bacolod", d: "Bacolod City, Negros Occidental, 6100, Philippines", lat: 10.6765, lon: 122.9509, t: "city", c: "communities", city: "Bacolod", state: "Negros Occidental" },
    { n: "Talisay", d: "Talisay, Negros Occidental, Negros Island Region, 6115, Philippines", lat: 10.7397, lon: 122.9691, t: "city", c: "communities", city: "Talisay", state: "Negros Occidental" },
    { n: "Silay", d: "Silay City, Negros Occidental, 6116, Philippines", lat: 10.7963, lon: 122.9754, t: "city", c: "communities", city: "Silay", state: "Negros Occidental" },
    { n: "Bago", d: "Bago City, Negros Occidental, 6101, Philippines", lat: 10.5378, lon: 122.8375, t: "city", c: "communities", city: "Bago", state: "Negros Occidental" },
    { n: "Cadiz", d: "Cadiz City, Negros Occidental, 6121, Philippines", lat: 10.9575, lon: 123.2986, t: "city", c: "communities", city: "Cadiz", state: "Negros Occidental" },
    { n: "Sagay", d: "Sagay City, Negros Occidental, 6122, Philippines", lat: 10.8986, lon: 123.4189, t: "city", c: "communities", city: "Sagay", state: "Negros Occidental" },
    { n: "Victorias", d: "Victorias City, Negros Occidental, 6119, Philippines", lat: 10.9000, lon: 123.0833, t: "city", c: "communities", city: "Victorias", state: "Negros Occidental" },
    { n: "San Carlos", d: "San Carlos City, Negros Occidental, 6127, Philippines", lat: 10.4850, lon: 123.4194, t: "city", c: "communities", city: "San Carlos", state: "Negros Occidental" },
    { n: "Kabankalan", d: "Kabankalan City, Negros Occidental, 6111, Philippines", lat: 9.9922, lon: 122.8142, t: "city", c: "communities", city: "Kabankalan", state: "Negros Occidental" },
    { n: "Sipalay", d: "Sipalay City, Negros Occidental, 6113, Philippines", lat: 9.7500, lon: 122.4000, t: "city", c: "communities", city: "Sipalay", state: "Negros Occidental" },
    { n: "Himamaylan", d: "Himamaylan City, Negros Occidental, 6108, Philippines", lat: 10.0983, lon: 122.8683, t: "city", c: "communities", city: "Himamaylan", state: "Negros Occidental" },
    { n: "La Carlota", d: "La Carlota City, Negros Occidental, 6130, Philippines", lat: 10.4222, lon: 122.9236, t: "city", c: "communities", city: "La Carlota", state: "Negros Occidental" },
    { n: "Escalante", d: "Escalante City, Negros Occidental, 6124, Philippines", lat: 10.8400, lon: 123.4986, t: "city", c: "communities", city: "Escalante", state: "Negros Occidental" },
    { n: "Binalbagan", d: "Binalbagan, Negros Occidental, 6107, Philippines", lat: 10.1931, lon: 122.9092, t: "town", c: "communities", city: "Binalbagan", state: "Negros Occidental" },
    { n: "Calatrava", d: "Calatrava, Negros Occidental, 6126, Philippines", lat: 10.5956, lon: 123.4831, t: "town", c: "communities", city: "Calatrava", state: "Negros Occidental" },
    { n: "Candoni", d: "Candoni, Negros Occidental, 6110, Philippines", lat: 9.8167, lon: 122.6833, t: "town", c: "communities", city: "Candoni", state: "Negros Occidental" },
    { n: "Cauayan", d: "Cauayan, Negros Occidental, 6112, Philippines", lat: 9.9722, lon: 122.6289, t: "town", c: "communities", city: "Cauayan", state: "Negros Occidental" },
    { n: "E.B. Magalona", d: "Enrique B. Magalona, Negros Occidental, 6118, Philippines", lat: 10.8456, lon: 123.0039, t: "town", c: "communities", city: "E.B. Magalona", state: "Negros Occidental" },
    { n: "Hinigaran", d: "Hinigaran, Negros Occidental, 6106, Philippines", lat: 10.2708, lon: 122.8508, t: "town", c: "communities", city: "Hinigaran", state: "Negros Occidental" },
    { n: "Hinoba-an", d: "Hinoba-an, Negros Occidental, 6114, Philippines", lat: 9.5833, lon: 122.5000, t: "town", c: "communities", city: "Hinoba-an", state: "Negros Occidental" },
    { n: "Ilog", d: "Ilog, Negros Occidental, 6109, Philippines", lat: 10.0306, lon: 122.7758, t: "town", c: "communities", city: "Ilog", state: "Negros Occidental" },
    { n: "Isabela", d: "Isabela, Negros Occidental, 6128, Philippines", lat: 10.2039, lon: 122.9886, t: "town", c: "communities", city: "Isabela", state: "Negros Occidental" },
    { n: "La Castellana", d: "La Castellana, Negros Occidental, 6131, Philippines", lat: 10.3347, lon: 123.0231, t: "town", c: "communities", city: "La Castellana", state: "Negros Occidental" },
    { n: "Manapla", d: "Manapla, Negros Occidental, 6120, Philippines", lat: 10.9567, lon: 123.1189, t: "town", c: "communities", city: "Manapla", state: "Negros Occidental" },
    { n: "Moises Padilla", d: "Moises Padilla, Negros Occidental, 6132, Philippines", lat: 10.2747, lon: 123.0806, t: "town", c: "communities", city: "Moises Padilla", state: "Negros Occidental" },
    { n: "Murcia", d: "Murcia, Negros Occidental, 6129, Philippines", lat: 10.6039, lon: 123.0417, t: "town", c: "communities", city: "Murcia", state: "Negros Occidental" },
    { n: "Pontevedra", d: "Pontevedra, Negros Occidental, 6105, Philippines", lat: 10.3667, lon: 122.8667, t: "town", c: "communities", city: "Pontevedra", state: "Negros Occidental" },
    { n: "Pulupandan", d: "Pulupandan, Negros Occidental, 6102, Philippines", lat: 10.5186, lon: 122.7989, t: "town", c: "communities", city: "Pulupandan", state: "Negros Occidental" },
    { n: "Don Salvador Benedicto", d: "Don Salvador Benedicto, Negros Occidental, 6133, Philippines", lat: 10.5694, lon: 123.2361, t: "town", c: "communities", city: "Salvador Benedicto", state: "Negros Occidental" },
    { n: "San Enrique", d: "San Enrique, Negros Occidental, 6104, Philippines", lat: 10.4181, lon: 122.8533, t: "town", c: "communities", city: "San Enrique", state: "Negros Occidental" },
    { n: "Toboso", d: "Toboso, Negros Occidental, 6125, Philippines", lat: 10.7167, lon: 123.5167, t: "town", c: "communities", city: "Toboso", state: "Negros Occidental" },
    { n: "Valladolid", d: "Valladolid, Negros Occidental, 6103, Philippines", lat: 10.4619, lon: 122.8336, t: "town", c: "communities", city: "Valladolid", state: "Negros Occidental" },

    // --- NEGROS ORIENTAL CITIES & MUNICIPALITIES ---
    { n: "Dumaguete", d: "Dumaguete City, Negros Oriental, 6200, Philippines", lat: 9.3068, lon: 123.3054, t: "city", c: "communities", city: "Dumaguete", state: "Negros Oriental" },
    { n: "Bais", d: "Bais City, Negros Oriental, 6206, Philippines", lat: 9.5906, lon: 123.1219, t: "city", c: "communities", city: "Bais", state: "Negros Oriental" },
    { n: "Bayawan", d: "Bayawan City, Negros Oriental, 6221, Philippines", lat: 9.3667, lon: 122.8000, t: "city", c: "communities", city: "Bayawan", state: "Negros Oriental" },
    { n: "Canlaon", d: "Canlaon City, Negros Oriental, 6223, Philippines", lat: 10.3861, lon: 123.2272, t: "city", c: "communities", city: "Canlaon", state: "Negros Oriental" },
    { n: "Guihulngan", d: "Guihulngan City, Negros Oriental, 6214, Philippines", lat: 10.1203, lon: 123.2731, t: "city", c: "communities", city: "Guihulngan", state: "Negros Oriental" },
    { n: "Tanjay", d: "Tanjay City, Negros Oriental, 6204, Philippines", lat: 9.5167, lon: 123.1500, t: "city", c: "communities", city: "Tanjay", state: "Negros Oriental" },
    { n: "Amlan", d: "Amlan, Negros Oriental, 6203, Philippines", lat: 9.4608, lon: 123.2325, t: "town", c: "communities", city: "Amlan", state: "Negros Oriental" },
    { n: "Ayungon", d: "Ayungon, Negros Oriental, 6210, Philippines", lat: 9.8500, lon: 123.1500, t: "town", c: "communities", city: "Ayungon", state: "Negros Oriental" },
    { n: "Bacong", d: "Bacong, Negros Oriental, 6216, Philippines", lat: 9.2458, lon: 123.2975, t: "town", c: "communities", city: "Bacong", state: "Negros Oriental" },
    { n: "Basay", d: "Basay, Negros Oriental, 6222, Philippines", lat: 9.4000, lon: 122.6667, t: "town", c: "communities", city: "Basay", state: "Negros Oriental" },
    { n: "Bindoy", d: "Bindoy, Negros Oriental, 6209, Philippines", lat: 9.7667, lon: 123.1500, t: "town", c: "communities", city: "Bindoy", state: "Negros Oriental" },
    { n: "Dauin", d: "Dauin, Negros Oriental, 6217, Philippines", lat: 9.1917, lon: 123.2694, t: "town", c: "communities", city: "Dauin", state: "Negros Oriental" },
    { n: "Jimalalud", d: "Jimalalud, Negros Oriental, 6212, Philippines", lat: 9.9833, lon: 123.2000, t: "town", c: "communities", city: "Jimalalud", state: "Negros Oriental" },
    { n: "La Libertad", d: "La Libertad, Negros Oriental, 6213, Philippines", lat: 10.0333, lon: 123.2333, t: "town", c: "communities", city: "La Libertad", state: "Negros Oriental" },
    { n: "Mabinay", d: "Mabinay, Negros Oriental, 6207, Philippines", lat: 9.7275, lon: 122.9250, t: "town", c: "communities", city: "Mabinay", state: "Negros Oriental" },
    { n: "Manjuyod", d: "Manjuyod, Negros Oriental, 6208, Philippines", lat: 9.6833, lon: 123.1500, t: "town", c: "communities", city: "Manjuyod", state: "Negros Oriental" },
    { n: "Pamplona", d: "Pamplona, Negros Oriental, 6205, Philippines", lat: 9.4667, lon: 123.1167, t: "town", c: "communities", city: "Pamplona", state: "Negros Oriental" },
    { n: "San Jose", d: "San Jose, Negros Oriental, 6202, Philippines", lat: 9.4167, lon: 123.2333, t: "town", c: "communities", city: "San Jose", state: "Negros Oriental" },
    { n: "Santa Catalina", d: "Santa Catalina, Negros Oriental, 6220, Philippines", lat: 9.3333, lon: 122.8667, t: "town", c: "communities", city: "Santa Catalina", state: "Negros Oriental" },
    { n: "Siaton", d: "Siaton, Negros Oriental, 6219, Philippines", lat: 9.0625, lon: 123.0375, t: "town", c: "communities", city: "Siaton", state: "Negros Oriental" },
    { n: "Sibulan", d: "Sibulan, Negros Oriental, 6201, Philippines", lat: 9.3564, lon: 123.2844, t: "town", c: "communities", city: "Sibulan", state: "Negros Oriental" },
    { n: "Tayasan", d: "Tayasan, Negros Oriental, 6211, Philippines", lat: 9.9167, lon: 123.1667, t: "town", c: "communities", city: "Tayasan", state: "Negros Oriental" },
    { n: "Valencia", d: "Valencia, Negros Oriental, 6215, Philippines", lat: 9.2817, lon: 123.2458, t: "town", c: "communities", city: "Valencia", state: "Negros Oriental" },
    { n: "Vallehermoso", d: "Vallehermoso, Negros Oriental, 6224, Philippines", lat: 10.3333, lon: 123.3333, t: "town", c: "communities", city: "Vallehermoso", state: "Negros Oriental" },
    { n: "Zamboanguita", d: "Zamboanguita, Negros Oriental, 6218, Philippines", lat: 9.1000, lon: 123.1972, t: "town", c: "communities", city: "Zamboanguita", state: "Negros Oriental" },

    // --- TALISAY BARANGAYS, PUROKS & LANDMARKS ---
    { n: "Zone 1", d: "Domingo Lizares Street, Purok Manpower, Zone 1, Talisay, Negros Occidental, 6115, Philippines", lat: 10.7380, lon: 122.9660, t: "neighbourhood", c: "communities", city: "Talisay", state: "Negros Occidental" },
    { n: "Zone 2", d: "Zone 2, Talisay, Negros Occidental, 6115, Philippines", lat: 10.7390, lon: 122.9680, t: "neighbourhood", c: "communities", city: "Talisay", state: "Negros Occidental" },
    { n: "Zone 3", d: "Zone 3, Talisay, Negros Occidental, 6115, Philippines", lat: 10.7410, lon: 122.9700, t: "neighbourhood", c: "communities", city: "Talisay", state: "Negros Occidental" },
    { n: "Zone 4", d: "Zone 4, Talisay, Negros Occidental, 6115, Philippines", lat: 10.7420, lon: 122.9720, t: "neighbourhood", c: "communities", city: "Talisay", state: "Negros Occidental" },
    { n: "Zone 5", d: "Zone 5, Talisay, Negros Occidental, 6115, Philippines", lat: 10.7370, lon: 122.9730, t: "neighbourhood", c: "communities", city: "Talisay", state: "Negros Occidental" },
    { n: "Zone 6", d: "Zone 6, Talisay, Negros Occidental, 6115, Philippines", lat: 10.7350, lon: 122.9690, t: "neighbourhood", c: "communities", city: "Talisay", state: "Negros Occidental" },
    { n: "Zone 7", d: "Zone 7, Talisay, Negros Occidental, 6115, Philippines", lat: 10.7340, lon: 122.9670, t: "neighbourhood", c: "communities", city: "Talisay", state: "Negros Occidental" },
    { n: "Zone 8", d: "Zone 8, Talisay, Negros Occidental, 6115, Philippines", lat: 10.7330, lon: 122.9650, t: "neighbourhood", c: "communities", city: "Talisay", state: "Negros Occidental" },
    { n: "Zone 9", d: "Zone 9, Talisay, Negros Occidental, 6115, Philippines", lat: 10.7360, lon: 122.9630, t: "neighbourhood", c: "communities", city: "Talisay", state: "Negros Occidental" },
    { n: "Zone 10", d: "Zone 10, Talisay, Negros Occidental, 6115, Philippines", lat: 10.7400, lon: 122.9640, t: "neighbourhood", c: "communities", city: "Talisay", state: "Negros Occidental" },
    { n: "Zone 11", d: "Zone 11, Talisay, Negros Occidental, 6115, Philippines", lat: 10.7440, lon: 122.9650, t: "neighbourhood", c: "communities", city: "Talisay", state: "Negros Occidental" },
    { n: "Zone 12", d: "Zone 12, Talisay, Negros Occidental, 6115, Philippines", lat: 10.7460, lon: 122.9670, t: "neighbourhood", c: "communities", city: "Talisay", state: "Negros Occidental" },
    { n: "Zone 12-A", d: "Zone 12-A, Talisay, Negros Occidental, 6115, Philippines", lat: 10.7470, lon: 122.9680, t: "neighbourhood", c: "communities", city: "Talisay", state: "Negros Occidental" },
    { n: "Zone 14", d: "Zone 14, Talisay, Negros Occidental, 6115, Philippines", lat: 10.7490, lon: 122.9710, t: "neighbourhood", c: "communities", city: "Talisay", state: "Negros Occidental" },
    { n: "Zone 15", d: "Zone 15, Talisay, Negros Occidental, 6115, Philippines", lat: 10.7510, lon: 122.9730, t: "neighbourhood", c: "communities", city: "Talisay", state: "Negros Occidental" },
    { n: "Bubog", d: "Barangay Bubog, Talisay, Negros Occidental, 6115, Philippines", lat: 10.7250, lon: 122.9850, t: "village", c: "communities", city: "Talisay", state: "Negros Occidental" },
    { n: "Concepcion", d: "Barangay Concepcion, Talisay, Negros Occidental, 6115, Philippines", lat: 10.7560, lon: 122.9980, t: "village", c: "communities", city: "Talisay", state: "Negros Occidental" },
    { n: "Dos Hermanas", d: "Barangay Dos Hermanas, Talisay, Negros Occidental, 6115, Philippines", lat: 10.7480, lon: 123.0300, t: "village", c: "communities", city: "Talisay", state: "Negros Occidental" },
    { n: "Efigenio Lizares", d: "Barangay Efigenio Lizares, Talisay, Negros Occidental, 6115, Philippines", lat: 10.7300, lon: 122.9700, t: "village", c: "communities", city: "Talisay", state: "Negros Occidental" },
    { n: "Katilingban", d: "Barangay Katilingban, Talisay, Negros Occidental, 6115, Philippines", lat: 10.7200, lon: 122.9600, t: "village", c: "communities", city: "Talisay", state: "Negros Occidental" },
    { n: "Matab-ang", d: "Barangay Matab-ang, Talisay, Negros Occidental, 6115, Philippines", lat: 10.7100, lon: 122.9750, t: "village", c: "communities", city: "Talisay", state: "Negros Occidental" },
    { n: "San Fernando", d: "Barangay San Fernando, Talisay, Negros Occidental, 6115, Philippines", lat: 10.7350, lon: 123.0100, t: "village", c: "communities", city: "Talisay", state: "Negros Occidental" },
    { n: "The Ruins", d: "The Ruins, Hda. Sta. Maria, Talisay, Negros Occidental, 6115, Philippines", lat: 10.7092, lon: 122.9825, t: "monument", c: "places", city: "Talisay", state: "Negros Occidental" },
    { n: "Carmela Executive Village", d: "Carmela Executive Village, Talisay, Negros Occidental, 6115, Philippines", lat: 10.7365, lon: 122.9710, t: "residential", c: "communities", city: "Talisay", state: "Negros Occidental" },

    // --- BACOLOD CITY BARANGAYS & LANDMARKS ---
    { n: "Mandalagan", d: "Barangay Mandalagan, Bacolod City, Negros Occidental, 6100, Philippines", lat: 10.6975, lon: 122.9620, t: "suburb", c: "communities", city: "Bacolod", state: "Negros Occidental" },
    { n: "Bata", d: "Barangay Bata, Bacolod City, Negros Occidental, 6100, Philippines", lat: 10.7080, lon: 122.9650, t: "suburb", c: "communities", city: "Bacolod", state: "Negros Occidental" },
    { n: "Villamonte", d: "Barangay Villamonte, Bacolod City, Negros Occidental, 6100, Philippines", lat: 10.6750, lon: 122.9680, t: "suburb", c: "communities", city: "Bacolod", state: "Negros Occidental" },
    { n: "Singcang-Airport", d: "Barangay Singcang-Airport, Bacolod City, Negros Occidental, 6100, Philippines", lat: 10.6450, lon: 122.9420, t: "suburb", c: "communities", city: "Bacolod", state: "Negros Occidental" },
    { n: "Taculing", d: "Barangay Taculing, Bacolod City, Negros Occidental, 6100, Philippines", lat: 10.6550, lon: 122.9580, t: "suburb", c: "communities", city: "Bacolod", state: "Negros Occidental" },
    { n: "Mansilingan", d: "Barangay Mansilingan, Bacolod City, Negros Occidental, 6100, Philippines", lat: 10.6380, lon: 122.9890, t: "suburb", c: "communities", city: "Bacolod", state: "Negros Occidental" },
    { n: "Alijis", d: "Barangay Alijis, Bacolod City, Negros Occidental, 6100, Philippines", lat: 10.6350, lon: 122.9650, t: "suburb", c: "communities", city: "Bacolod", state: "Negros Occidental" },
    { n: "Banago", d: "Barangay Banago, Bacolod City, Negros Occidental, 6100, Philippines", lat: 10.6950, lon: 122.9450, t: "suburb", c: "communities", city: "Bacolod", state: "Negros Occidental" },
    { n: "Estefania", d: "Barangay Estefania, Bacolod City, Negros Occidental, 6100, Philippines", lat: 10.6780, lon: 122.9850, t: "suburb", c: "communities", city: "Bacolod", state: "Negros Occidental" },
    { n: "Tangub", d: "Barangay Tangub, Bacolod City, Negros Occidental, 6100, Philippines", lat: 10.6220, lon: 122.9350, t: "suburb", c: "communities", city: "Bacolod", state: "Negros Occidental" },
    { n: "Sum-ag", d: "Barangay Sum-ag, Bacolod City, Negros Occidental, 6100, Philippines", lat: 10.6050, lon: 122.9250, t: "suburb", c: "communities", city: "Bacolod", state: "Negros Occidental" },
    { n: "Pahanocoy", d: "Barangay Pahanocoy, Bacolod City, Negros Occidental, 6100, Philippines", lat: 10.5900, lon: 122.9180, t: "suburb", c: "communities", city: "Bacolod", state: "Negros Occidental" },
    { n: "Granada", d: "Barangay Granada, Bacolod City, Negros Occidental, 6100, Philippines", lat: 10.6850, lon: 123.0150, t: "suburb", c: "communities", city: "Bacolod", state: "Negros Occidental" },
    { n: "Handumanan", d: "Barangay Handumanan, Bacolod City, Negros Occidental, 6100, Philippines", lat: 10.6150, lon: 122.9950, t: "suburb", c: "communities", city: "Bacolod", state: "Negros Occidental" },
    { n: "Felisa", d: "Barangay Felisa, Bacolod City, Negros Occidental, 6100, Philippines", lat: 10.6120, lon: 122.9720, t: "suburb", c: "communities", city: "Bacolod", state: "Negros Occidental" },
    { n: "Vista Alegre", d: "Barangay Vista Alegre, Bacolod City, Negros Occidental, 6100, Philippines", lat: 10.6650, lon: 123.0050, t: "suburb", c: "communities", city: "Bacolod", state: "Negros Occidental" },
    { n: "Montevista", d: "Barangay Montevista, Bacolod City, Negros Occidental, 6100, Philippines", lat: 10.6720, lon: 122.9750, t: "suburb", c: "communities", city: "Bacolod", state: "Negros Occidental" },
    { n: "Punta Taytay", d: "Barangay Punta Taytay, Bacolod City, Negros Occidental, 6100, Philippines", lat: 10.5750, lon: 122.9050, t: "suburb", c: "communities", city: "Bacolod", state: "Negros Occidental" },
    { n: "Lacson Street", d: "Lacson Street, Bacolod City, Negros Occidental, 6100, Philippines", lat: 10.6780, lon: 122.9550, t: "road", c: "roads", city: "Bacolod", state: "Negros Occidental" },
    { n: "Bacolod City Government Center", d: "Bacolod City Government Center (BCGC), Circumferential Rd, Bacolod City, Negros Occidental, 6100, Philippines", lat: 10.6628, lon: 122.9764, t: "public_building", c: "places", city: "Bacolod", state: "Negros Occidental" },
    { n: "Capitol Park and Lagoon", d: "Capitol Park and Lagoon, Lacson St, Bacolod City, Negros Occidental, 6100, Philippines", lat: 10.6740, lon: 122.9515, t: "park", c: "places", city: "Bacolod", state: "Negros Occidental" },
    { n: "SM City Bacolod", d: "SM City Bacolod, Reclamation Area, Bacolod City, Negros Occidental, 6100, Philippines", lat: 10.6710, lon: 122.9420, t: "mall", c: "places", city: "Bacolod", state: "Negros Occidental" },
    { n: "Robinsons Place Bacolod", d: "Robinsons Place Bacolod, Lacson St, Mandalagan, Bacolod City, Negros Occidental, 6100, Philippines", lat: 10.6890, lon: 122.9560, t: "mall", c: "places", city: "Bacolod", state: "Negros Occidental" },
    { n: "Ayala Malls Capitol Central", d: "Ayala Malls Capitol Central, Gatuslao St, Bacolod City, Negros Occidental, 6100, Philippines", lat: 10.6760, lon: 122.9530, t: "mall", c: "places", city: "Bacolod", state: "Negros Occidental" },
    { n: "Panaad Park and Stadium", d: "Panaad Park and Stadium, Mansilingan, Bacolod City, Negros Occidental, 6100, Philippines", lat: 10.6350, lon: 122.9780, t: "stadium", c: "places", city: "Bacolod", state: "Negros Occidental" },

    // --- SILAY CITY BARANGAYS & LANDMARKS ---
    { n: "Rizal", d: "Barangay Rizal, Silay City, Negros Occidental, 6116, Philippines", lat: 10.7980, lon: 122.9720, t: "village", c: "communities", city: "Silay", state: "Negros Occidental" },
    { n: "Guinhalaran", d: "Barangay Guinhalaran, Silay City, Negros Occidental, 6116, Philippines", lat: 10.7850, lon: 122.9680, t: "village", c: "communities", city: "Silay", state: "Negros Occidental" },
    { n: "Mambulac", d: "Barangay Mambulac, Silay City, Negros Occidental, 6116, Philippines", lat: 10.8050, lon: 122.9620, t: "village", c: "communities", city: "Silay", state: "Negros Occidental" },
    { n: "Lantad", d: "Barangay Lantad, Silay City, Negros Occidental, 6116, Philippines", lat: 10.8120, lon: 122.9750, t: "village", c: "communities", city: "Silay", state: "Negros Occidental" },
    { n: "E. Lopez", d: "Barangay E. Lopez, Silay City, Negros Occidental, 6116, Philippines", lat: 10.8250, lon: 123.0150, t: "village", c: "communities", city: "Silay", state: "Negros Occidental" },
    { n: "Hawaiian", d: "Barangay Hawaiian, Silay City, Negros Occidental, 6116, Philippines", lat: 10.8350, lon: 123.0450, t: "village", c: "communities", city: "Silay", state: "Negros Occidental" },
    { n: "Bacolod-Silay Airport", d: "Bacolod-Silay International Airport, Silay City, Negros Occidental, 6116, Philippines", lat: 10.7767, lon: 123.0150, t: "aerodrome", c: "places", city: "Silay", state: "Negros Occidental" },

    // --- BAGO CITY BARANGAYS ---
    { n: "Caridad", d: "Barangay Caridad, Bago City, Negros Occidental, 6101, Philippines", lat: 10.5350, lon: 122.8350, t: "village", c: "communities", city: "Bago", state: "Negros Occidental" },
    { n: "Balingasag", d: "Barangay Balingasag, Bago City, Negros Occidental, 6101, Philippines", lat: 10.5450, lon: 122.8420, t: "village", c: "communities", city: "Bago", state: "Negros Occidental" },
    { n: "Ma-ao", d: "Barangay Ma-ao, Bago City, Negros Occidental, 6101, Philippines", lat: 10.4750, lon: 122.9550, t: "village", c: "communities", city: "Bago", state: "Negros Occidental" },
    { n: "Sampinit", d: "Barangay Sampinit, Bago City, Negros Occidental, 6101, Philippines", lat: 10.5520, lon: 122.8480, t: "village", c: "communities", city: "Bago", state: "Negros Occidental" },
    { n: "Taloc", d: "Barangay Taloc, Bago City, Negros Occidental, 6101, Philippines", lat: 10.5750, lon: 122.8750, t: "village", c: "communities", city: "Bago", state: "Negros Occidental" },

    // --- DUMAGUETE CITY BARANGAYS & LANDMARKS ---
    { n: "Daro", d: "Barangay Daro, Dumaguete City, Negros Oriental, 6200, Philippines", lat: 9.3150, lon: 123.2980, t: "suburb", c: "communities", city: "Dumaguete", state: "Negros Oriental" },
    { n: "Taclobo", d: "Barangay Taclobo, Dumaguete City, Negros Oriental, 6200, Philippines", lat: 9.3080, lon: 123.3020, t: "suburb", c: "communities", city: "Dumaguete", state: "Negros Oriental" },
    { n: "Piapi", d: "Barangay Piapi, Dumaguete City, Negros Oriental, 6200, Philippines", lat: 9.3180, lon: 123.3080, t: "suburb", c: "communities", city: "Dumaguete", state: "Negros Oriental" },
    { n: "Bantayan", d: "Barangay Bantayan, Dumaguete City, Negros Oriental, 6200, Philippines", lat: 9.3250, lon: 123.3100, t: "suburb", c: "communities", city: "Dumaguete", state: "Negros Oriental" },
    { n: "Candau-ay", d: "Barangay Candau-ay, Dumaguete City, Negros Oriental, 6200, Philippines", lat: 9.3120, lon: 123.2750, t: "suburb", c: "communities", city: "Dumaguete", state: "Negros Oriental" },
    { n: "Bagacay", d: "Barangay Bagacay, Dumaguete City, Negros Oriental, 6200, Philippines", lat: 9.3020, lon: 123.2920, t: "suburb", c: "communities", city: "Dumaguete", state: "Negros Oriental" },
    { n: "Bajumpandan", d: "Barangay Bajumpandan, Dumaguete City, Negros Oriental, 6200, Philippines", lat: 9.2880, lon: 123.2850, t: "suburb", c: "communities", city: "Dumaguete", state: "Negros Oriental" },
    { n: "Banilad", d: "Barangay Banilad, Dumaguete City, Negros Oriental, 6200, Philippines", lat: 9.2780, lon: 123.2950, t: "suburb", c: "communities", city: "Dumaguete", state: "Negros Oriental" },
    { n: "Calindagan", d: "Barangay Calindagan, Dumaguete City, Negros Oriental, 6200, Philippines", lat: 9.2950, lon: 123.3050, t: "suburb", c: "communities", city: "Dumaguete", state: "Negros Oriental" },
    { n: "Junob", d: "Barangay Junob, Dumaguete City, Negros Oriental, 6200, Philippines", lat: 9.2850, lon: 123.2800, t: "suburb", c: "communities", city: "Dumaguete", state: "Negros Oriental" },
    { n: "Rizal Boulevard", d: "Rizal Boulevard, Dumaguete City, Negros Oriental, 6200, Philippines", lat: 9.3075, lon: 123.3120, t: "promenade", c: "places", city: "Dumaguete", state: "Negros Oriental" },
    { n: "Silliman University", d: "Silliman University, Hibbard Ave, Dumaguete City, Negros Oriental, 6200, Philippines", lat: 9.3125, lon: 123.3075, t: "university", c: "places", city: "Dumaguete", state: "Negros Oriental" }
  ];

  function searchNegros(query, type = 'all') {
    const qNorm = normalize(query);
    if (qNorm.length < 2) return [];
    const words = qNorm.split(' ').filter(w => w.length > 0);
    const compact = qNorm.replaceAll(' ', '');

    const matches = [];
    for (const item of NEGROS_DIRECTORY) {
      if (type !== 'all' && item.c !== type) continue;
      const nameNorm = normalize(item.n);
      const dispNorm = normalize(item.d);
      const isWordMatch = words.every(w => nameNorm.includes(w) || dispNorm.includes(w));
      if (!isWordMatch) continue;

      let score = 50;
      if (nameNorm === qNorm) score += 200;
      else if (nameNorm.replaceAll(' ', '') === compact) score += 180;
      else if (nameNorm.startsWith(qNorm)) score += 120;
      else if (dispNorm.includes(qNorm)) score += 60;

      matches.push({
        item: {
          name: item.n,
          display_name: item.d,
          lat: String(item.lat),
          lon: String(item.lon),
          class: item.c === 'roads' ? 'highway' : item.c === 'communities' ? 'place' : 'amenity',
          type: item.t,
          category: item.c === 'roads' ? 'highway' : item.c === 'communities' ? 'place' : 'amenity',
          address: {
            city: item.city || item.n,
            state: item.state,
            country_code: 'ph'
          },
          is_negros: true,
          is_local_directory: true
        },
        score
      });
    }

    return matches.sort((a, b) => b.score - a.score).map(m => m.item).slice(0, 15);
  }

  function searchSavedSites(records, query) {
    if (!records) return [];
    const qNorm = normalize(query);
    if (qNorm.length < 2) return [];
    const words = qNorm.split(' ').filter(w => w.length > 0);
    const matches = [];

    const list = records instanceof Map ? Array.from(records.values()) : Array.isArray(records) ? records : [];
    for (const site of list) {
      if (!site) continue;
      const label = site.label || '';
      const address = site.address || '';
      const lat = site.latitude != null ? Number(site.latitude) : null;
      const lon = site.longitude != null ? Number(site.longitude) : null;
      if (lat == null || lon == null || !Number.isFinite(lat) || !Number.isFinite(lon)) continue;

      const combinedText = normalize(`${label} ${address}`);
      const isMatch = words.every(w => combinedText.includes(w));
      if (!isMatch) continue;

      matches.push({
        name: label,
        display_name: `${label}${address ? ', ' + address : ''}`,
        lat: String(lat),
        lon: String(lon),
        class: 'place',
        type: 'establishment',
        category: 'place',
        address: {
          amenity: label,
          country_code: 'ph'
        },
        is_negros: isNegros({ lat, lon, display_name: address }),
        is_agency_site: true
      });
    }

    return matches.slice(0, 10);
  }

  function mergeResults(osmResults, localResults) {
    const combined = [...(Array.isArray(osmResults) ? osmResults : [])];
    const seenNames = new Set(combined.map(r => normalize(r.name || r.display_name?.split(',')[0])));
    if (Array.isArray(localResults)) {
      for (const loc of localResults) {
        const locName = normalize(loc.name || loc.display_name?.split(',')[0]);
        if (!seenNames.has(locName)) {
          combined.push(loc);
          seenNames.add(locName);
        }
      }
    }
    return combined;
  }

  return Object.freeze({
    normalize,
    variants,
    kind,
    filter,
    matchesSite,
    isNegros,
    searchNegros,
    searchSavedSites,
    mergeResults,
    NEGROS_DIRECTORY
  });
});

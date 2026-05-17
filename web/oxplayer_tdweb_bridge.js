/**
 * Minimal bridge: Dart registers `window.oxplayerTdwebDartPush(jsonString)`,
 * then calls `oxplayerTdweb.createClient({ instanceEpoch })` and `oxplayerTdweb.send(json)`.
 * Requires `tdweb/tdweb.js` loaded first. The UMD global may be TdClient or
 * `{ default: TdClient }` (webpack ESM interop).
 */
(function () {
  'use strict';

  try {
    if (typeof globalThis.__OXPLAYER_TDWEB_PUBLIC_PATH__ === 'undefined') {
      globalThis.__OXPLAYER_TDWEB_PUBLIC_PATH__ = new URL(
        'tdweb/',
        document.baseURI,
      ).href;
    }
  } catch (_) {
    globalThis.__OXPLAYER_TDWEB_PUBLIC_PATH__ = 'tdweb/';
  }

  var client = null;

  function tdwebClass() {
    var g = typeof globalThis !== 'undefined' ? globalThis : window;
    var t = g.tdweb;
    if (typeof t === 'function') return t;
    if (t && typeof t.default === 'function') return t.default;
    throw new Error(
      'Global tdweb (TdClient) missing. Ensure web/tdweb/tdweb.js is copied (node scripts/sync-tdweb.mjs), '
        + 'served at the same origin as the app, and loads before oxplayer_tdweb_bridge.js (see web/index.html).',
    );
  }

  /**
   * tdweb worker [prepareQuery] expects setTdlibParameters under [parameters]; Dart tdlib 1.6
   * emits a flat object (database_directory at root) like libtdjson CLI.
   */
  function nestSetTdlibParametersForTdweb(obj) {
    if (!obj || obj['@type'] !== 'setTdlibParameters') return obj;
    if (obj.parameters && typeof obj.parameters === 'object') return obj;
    var out = { '@type': 'setTdlibParameters' };
    if (Object.prototype.hasOwnProperty.call(obj, '@extra')) {
      out['@extra'] = obj['@extra'];
    }
    var p = {};
    for (var k in obj) {
      if (!Object.prototype.hasOwnProperty.call(obj, k)) continue;
      if (k === '@type' || k === '@extra') continue;
      p[k] = obj[k];
    }
    if (!p['@type']) {
      p['@type'] = 'tdlibParameters';
    }
    out.parameters = p;
    return out;
  }

  function pushUpdate(u) {
    try {
      var t = u && u['@type'];
      if (t === 'updateFatalError') {
        // Worker passes a JS Error here; JSON.stringify(Error) becomes "{}" so Dart
        // never sees .message. Normalize to a plain string before stringify.
        var er = u && u.error;
        if (typeof er === 'string') {
          if (!er) {
            u = { '@type': 'updateFatalError', error: '(empty fatal string from TDLib)' };
          }
        } else if (er && typeof er.message === 'string' && er.message) {
          u = { '@type': 'updateFatalError', error: String(er.message) };
        } else if (er && (typeof er.stack === 'string') && er.stack) {
          u = { '@type': 'updateFatalError', error: String(er.stack) };
        } else if (er != null && typeof er === 'object') {
          var name = typeof er.name === 'string' ? er.name : 'Error';
          var msgAny = er.message || er.stack;
          if (typeof msgAny === 'string' && msgAny.trim()) {
            u = { '@type': 'updateFatalError', error: String(msgAny) };
          } else {
            u = {
              '@type': 'updateFatalError',
              error:
                'JS ' +
                name +
                ' (no message/stack; often WASM/IndexedDB or corrupt tdweb DB)',
            };
          }
        } else if (er != null) {
          u = { '@type': 'updateFatalError', error: String(er) };
        } else {
          u = {
            '@type': 'updateFatalError',
            error:
              'updateFatalError with no message (see browser DevTools console for worker errors)',
          };
        }
        console.error('[OX tdweb bridge] updateFatalError →', u.error);
      }
      if (t === 'updateAuthorizationState') {
        var inner =
          u.authorization_state && u.authorization_state['@type'];
        console.info('[OX tdweb bridge] updateAuthorizationState →', inner || '?');
      }
    } catch (_) {}
    var fn = window.oxplayerTdwebDartPush;
    if (typeof fn !== 'function') return;
    try {
      fn(JSON.stringify(u));
    } catch (e) {
      console.error('[oxplayer_tdweb_bridge] dart push failed', e);
    }
  }

  window.oxplayerTdweb = {
    /**
     * @param {{ instanceEpoch?: number, mode?: string }} opts
     * @returns {Promise<void>}
     */
    createClient: function (opts) {
      if (client) {
        return Promise.reject(new Error('TdClient already created'));
      }
      opts = opts || {};
      var epoch = opts.instanceEpoch != null ? opts.instanceEpoch : 0;
      var TdClient = tdwebClass();
      console.info('[OX tdweb bridge] createClient epoch=' + String(epoch));
      client = new TdClient({
        instanceName: 'oxplayer_td_' + String(epoch),
        mode: opts.mode || 'wasm',
        onUpdate: pushUpdate,
        useDatabase: true,
      });
      return Promise.resolve();
    },

    /** True after tdweb worker has fired `inited` (safe to call [send]). */
    isTdwebInited: function () {
      return !!(client && client.isInited);
    },

    /** @returns {Promise<void>} */
    closeClient: function () {
      if (!client) return Promise.resolve();
      try {
        client.close();
      } catch (e) {
        console.warn('[oxplayer_tdweb_bridge] client.close', e);
      }
      client = null;
      return Promise.resolve();
    },

    /**
     * @param {string} jsonStr
     * @returns {Promise<string>}
     */
    send: function (jsonStr) {
      if (!client) {
        return Promise.reject(new Error('TdClient not initialized'));
      }
      var q = JSON.parse(jsonStr);
      q = nestSetTdlibParametersForTdweb(q);
      var qt = q && q['@type'];
      if (qt) {
        console.info('[OX tdweb bridge] send →', qt);
      }
      return client.send(q).then(function (r) {
        return JSON.stringify(r);
      });
    },
  };
})();

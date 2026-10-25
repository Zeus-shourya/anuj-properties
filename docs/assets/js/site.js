/* Anuj Properties — site.js (no dependencies)
   - mobile menu + desktop dropdowns (disclosure pattern)
   - enquiry form: validation, WhatsApp hand-off, optional POST to a form endpoint
   - click-to-load Google map
   - conversion events, sent only when GA4 (gtag) or a dataLayer is present */
(function () {
  'use strict';
  var doc = document;
  var root = doc.documentElement;

  function track(name, params) {
    params = params || {};
    params.page_path = location.pathname;
    try {
      if (typeof window.gtag === 'function') window.gtag('event', name, params);
      else if (window.dataLayer && window.dataLayer.push) {
        var ev = { event: name };
        for (var k in params) ev[k] = params[k];
        window.dataLayer.push(ev);
      }
    } catch (e) { /* analytics must never break the page */ }
  }

  /* ---------- opened straight from disk (file://)? ----------
     Browsers don't open a folder's index.html locally, so point folder links at it.
     Never runs on the web, where the clean /contact/ style URLs stay as they are. */
  if (location.protocol === 'file:') {
    Array.prototype.forEach.call(doc.querySelectorAll('a[href]'), function (a) {
      var h = a.getAttribute('href');
      if (/^([a-z][a-z0-9+.-]*:|\/\/|#)/i.test(h)) return; // external, tel:, wa.me, in-page
      var i = h.search(/[?#]/);
      var path = i < 0 ? h : h.slice(0, i);
      if (/\/$/.test(path)) a.setAttribute('href', path + 'index.html' + (i < 0 ? '' : h.slice(i)));
    });
  }

  /* ---------- call / WhatsApp click tracking ---------- */
  doc.addEventListener('click', function (e) {
    var a = e.target.closest ? e.target.closest('a[href]') : null;
    if (!a) return;
    var href = a.getAttribute('href') || '';
    if (href.indexOf('tel:') === 0) track('click_to_call', { link_text: a.textContent.trim().slice(0, 40) });
    else if (href.indexOf('https://wa.me/') === 0) track('whatsapp_click', { link_text: a.textContent.trim().slice(0, 40) });
    else if (/google\.com\/maps\/dir/.test(href)) track('get_directions');
  });

  /* ---------- mobile menu ---------- */
  var toggle = doc.querySelector('.nav__toggle');
  var panel = doc.getElementById('nav-panel');
  function setNav(open) {
    toggle.setAttribute('aria-expanded', String(open));
    root.classList.toggle('nav-open', open);
    var label = toggle.querySelector('span');
    if (label) label.textContent = open ? 'Close' : 'Menu';
  }
  if (toggle && panel) {
    toggle.addEventListener('click', function () { setNav(toggle.getAttribute('aria-expanded') !== 'true'); });
    panel.addEventListener('click', function (e) { if (e.target.closest('a')) setNav(false); });
    var mq = window.matchMedia('(min-width: 960px)');
    var onMq = function (ev) { if (ev.matches) setNav(false); };
    if (mq.addEventListener) mq.addEventListener('change', onMq); else if (mq.addListener) mq.addListener(onMq);
  }

  /* ---------- desktop dropdowns ---------- */
  var subToggles = Array.prototype.slice.call(doc.querySelectorAll('.nav__sub-toggle'));
  function closeSubs(except) {
    subToggles.forEach(function (btn) {
      if (btn === except) return;
      btn.setAttribute('aria-expanded', 'false');
      btn.closest('.nav__item').classList.remove('is-open');
    });
  }
  subToggles.forEach(function (btn) {
    var item = btn.closest('.nav__item');
    btn.addEventListener('click', function () {
      var open = btn.getAttribute('aria-expanded') !== 'true';
      closeSubs(btn);
      btn.setAttribute('aria-expanded', String(open));
      item.classList.toggle('is-open', open);
    });
    item.addEventListener('focusout', function (e) {
      if (!item.contains(e.relatedTarget)) { btn.setAttribute('aria-expanded', 'false'); item.classList.remove('is-open'); }
    });
  });
  doc.addEventListener('click', function (e) { if (!e.target.closest('.nav__item')) closeSubs(); });
  doc.addEventListener('keydown', function (e) {
    if (e.key !== 'Escape') return;
    var openSub = doc.querySelector('.nav__sub-toggle[aria-expanded="true"]');
    if (openSub) { closeSubs(); openSub.focus(); return; }
    if (toggle && root.classList.contains('nav-open')) { setNav(false); toggle.focus(); }
  });

  /* ---------- enquiry form ---------- */
  var form = doc.querySelector('form[data-enquiry]');
  if (form) initForm(form);

  function initForm(form) {
    var waNumber = (form.getAttribute('action') || '').replace(/\D/g, '');
    var endpoint = form.getAttribute('data-endpoint') || '';
    var accessKey = form.getAttribute('data-key') || '';
    var status = form.querySelector('.form-status');
    var btn = form.querySelector('button[type="submit"]');
    var btnLabel = btn.querySelector('[data-label]');
    var btnText = btnLabel ? btnLabel.textContent : '';

    // presets from the page (e.g. the Omaxe City page pre-selects "Omaxe City")
    var intent = form.getAttribute('data-intent');
    if (intent) {
      var r = form.querySelector('input[name="intent"][value="' + intent + '"]');
      if (r) r.checked = true;
    }
    ['type', 'area'].forEach(function (name) {
      var v = form.getAttribute('data-' + name);
      var sel = form.elements[name];
      if (!v || !sel) return;
      for (var i = 0; i < sel.options.length; i++) if (sel.options[i].text === v) sel.selectedIndex = i;
    });

    function normPhone(v) {
      var d = String(v).replace(/\D/g, '');
      if (d.length === 12 && d.indexOf('91') === 0) d = d.slice(2);
      else if (d.length === 11 && d.charAt(0) === '0') d = d.slice(1);
      return /^[6-9]\d{9}$/.test(d) ? d : '';
    }
    var rules = {
      name: function (v) { return v.trim().length >= 2 ? '' : 'Please enter your name.'; },
      phone: function (v) { return normPhone(v) ? '' : 'Please enter a 10-digit Indian mobile number.'; }
    };
    function setError(el, msg) {
      var err = doc.getElementById(el.id + '-err');
      if (msg) el.setAttribute('aria-invalid', 'true'); else el.removeAttribute('aria-invalid');
      if (err) { err.textContent = msg; err.hidden = !msg; }
    }
    Object.keys(rules).forEach(function (k) {
      var el = form.elements[k];
      el.addEventListener('blur', function () { if (el.value.trim()) setError(el, rules[k](el.value)); });
      el.addEventListener('input', function () { if (el.getAttribute('aria-invalid')) setError(el, rules[k](el.value)); });
    });

    function val(name) {
      var el = form.elements[name];
      if (!el) return '';
      if (el.length && el[0] && el[0].type === 'radio') {
        for (var i = 0; i < el.length; i++) if (el[i].checked) return el[i].value;
        return '';
      }
      return (el.value || '').trim();
    }
    function compose(d) {
      var lines = ['Hi Anuj Properties,', 'I want to: ' + d.intent, 'Property: ' + d.type, 'Area: ' + d.area];
      if (d.budget) lines.push('Budget: ' + d.budget);
      lines.push('Name: ' + d.name, 'Mobile: ' + d.phone);
      if (d.message) lines.push('Note: ' + d.message);
      lines.push('(sent from your website: ' + location.pathname + ')');
      return lines.join('\n');
    }
    function esc(s) { return String(s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }
    function showStatus(kind, html) {
      status.className = 'form-status form-status--' + kind;
      status.innerHTML = html;
      status.hidden = false;
      status.focus();
    }
    var telLink = doc.querySelector('a[href^="tel:"]');
    var tel = telLink ? telLink.getAttribute('href') : '';
    var telText = tel.replace('tel:+91', '').replace(/(\d{5})(\d{5})/, '$1 $2');
    function buttons(waUrl) {
      return '<div class="btn-row"><a class="btn btn--wa btn--sm" href="' + esc(waUrl) + '">Open WhatsApp</a>' +
        (tel ? '<a class="btn btn--call btn--sm" href="' + esc(tel) + '">Call ' + esc(telText) + '</a>' : '') + '</div>';
    }
    function busy(on) {
      btn.disabled = on;
      if (on) btn.setAttribute('aria-busy', 'true'); else btn.removeAttribute('aria-busy');
      if (btnLabel) btnLabel.textContent = on ? 'Sending…' : btnText;
    }
    function openWhatsApp(url) {
      var w = null;
      try { w = window.open(url, '_blank'); } catch (e) { w = null; }
      if (w) { try { w.opener = null; } catch (e) {} } else { location.href = url; }
    }
    function send(d) {
      var body = new FormData();
      Object.keys(d).forEach(function (k) { body.append(k, d[k]); });
      body.append('subject', 'Website enquiry: ' + d.intent + ' ' + d.type + ' (' + d.area + ')');
      body.append('page', location.href);
      if (accessKey) body.append('access_key', accessKey);
      var ctrl = window.AbortController ? new AbortController() : null;
      var timer = setTimeout(function () { if (ctrl) ctrl.abort(); }, 12000);
      return fetch(endpoint, { method: 'POST', body: body, headers: { Accept: 'application/json' }, signal: ctrl ? ctrl.signal : undefined })
        .then(function (res) { clearTimeout(timer); if (!res.ok) throw new Error('HTTP ' + res.status); return res; },
              function (err) { clearTimeout(timer); throw err; });
    }

    form.addEventListener('submit', function (e) {
      e.preventDefault();
      if (btn.disabled) return;
      if (form.elements.company && form.elements.company.value) return; // spam trap
      var firstBad = null;
      Object.keys(rules).forEach(function (k) {
        var el = form.elements[k];
        var msg = rules[k](el.value);
        setError(el, msg);
        if (msg && !firstBad) firstBad = el;
      });
      if (firstBad) { firstBad.focus(); return; }

      var d = {
        intent: val('intent'), type: val('type'), area: val('area'), budget: val('budget'),
        name: val('name'), phone: normPhone(val('phone')), message: val('text')
      };
      var waUrl = 'https://wa.me/' + waNumber + '?text=' + encodeURIComponent(compose(d));
      track('generate_lead', { form_intent: d.intent, property_type: d.type, area: d.area, method: endpoint ? 'form' : 'whatsapp' });

      if (!endpoint) {
        openWhatsApp(waUrl);
        showStatus('ok', '<strong>WhatsApp is opening with your enquiry, ' + esc(d.name.split(' ')[0]) + '.</strong>' +
          'Tap send in WhatsApp to reach us. If it didn\'t open, use the button below or call us.' + buttons(waUrl));
        return;
      }
      busy(true);
      send(d).then(function () {
        busy(false);
        form.reset();
        showStatus('ok', '<strong>Thank you, ' + esc(d.name.split(' ')[0]) + '. Your enquiry has reached us.</strong>' +
          'We\'ll get back to you on ' + esc(d.phone) + '. For a quicker reply you can also send it on WhatsApp.' + buttons(waUrl));
      }, function () {
        busy(false);
        showStatus('err', '<strong>Sorry, that didn\'t go through.</strong>Please send your enquiry on WhatsApp or call us. Your details are kept in the form.' + buttons(waUrl));
      });
    });
  }

  /* ---------- click-to-load map ---------- */
  Array.prototype.forEach.call(doc.querySelectorAll('[data-map]'), function (box) {
    var b = box.querySelector('[data-map-load]');
    if (!b) return;
    b.addEventListener('click', function () {
      var f = doc.createElement('iframe');
      f.src = box.getAttribute('data-map');
      f.title = 'Google map showing the Anuj Properties office in Parsvnath City, Sonipat';
      f.setAttribute('loading', 'lazy');
      f.setAttribute('referrerpolicy', 'no-referrer-when-downgrade');
      f.setAttribute('allowfullscreen', '');
      box.appendChild(f);
      b.hidden = true;
      track('map_load');
    });
  });
})();

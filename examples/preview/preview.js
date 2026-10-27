/* Prévia de identidade: todos os números e nomes abaixo são FICTÍCIOS.
   Não utilizar em releases ou testes de dados oficiais. */
(() => {
  'use strict';
  const mockCities = {
    modelo: {
      name: 'Cidade Modelo, Goiás', short: 'CIDADE MODELO', sections: 34,
      a1: 3120, a2: 3655, b1: 2780, b2: 3101,
      others: 412, turnout1: 6610, turnout2: 6838, invalid1: 298, invalid2: 82
    },
    sereno: {
      name: 'Vale Sereno, Minas Gerais', short: 'VALE SERENO', sections: 45,
      a1: 4021, a2: 4400, b1: 2950, b2: 3415,
      others: 329, turnout1: 7700, turnout2: 8100, invalid1: 400, invalid2: 285
    }
  };

  const fmt = new Intl.NumberFormat('pt-BR');
  const signed = x => (x >= 0 ? '+' : '−') + fmt.format(Math.abs(x));
  const get = id => document.getElementById(id);
  const set = (id, value) => { const node = get(id); if (node) node.textContent = value; };
  const svgNS = 'http://www.w3.org/2000/svg';
  const svg = (tag, props = {}, text) => {
    const el = document.createElementNS(svgNS, tag);
    for (const [key, val] of Object.entries(props)) el.setAttribute(key, String(val));
    if (text != null) el.textContent = String(text);
    return el;
  };
  const cssToken = name => getComputedStyle(document.documentElement).getPropertyValue(name).trim();

  function updateChart(data) {
    const grid = get('chart-grid');
    const lines = get('chart-lines');
    grid.replaceChildren();
    lines.replaceChildren();
    const max = 5000, bottom = 258, top = 42, left = 66, x1 = 185, x2 = 538;
    const y = v => bottom - (v / max) * (bottom - top);
    const ink = cssToken('--color-muted');
    const border = cssToken('--color-border');
    for (const tick of [0, 2500, 5000]) {
      const yy = y(tick);
      grid.appendChild(svg('line', {x1: left, y1: yy, x2: 682, y2: yy, stroke: border, 'stroke-width': 1}));
      grid.appendChild(svg('text', {x: 55, y: yy + 5, fill: ink, 'font-size': 13, 'text-anchor': 'end'}, fmt.format(tick)));
    }
    for (const [x, label] of [[x1,'1º turno'],[x2,'2º turno']]) {
      grid.appendChild(svg('text', {x, y: 290, fill: ink, 'font-size': 13, 'text-anchor': 'middle'}, label));
    }
    const arr = [
      {name: 'A', color: cssToken('--color-candidate-a'), start: data.a1, end: data.a2, dy: -12},
      {name: 'B', color: cssToken('--color-candidate-b'), start: data.b1, end: data.b2, dy: 20}
    ];
    const near = Math.abs(y(data.a2)-y(data.b2)) < 25;
    for (const item of arr) {
      const y1 = y(item.start), y2 = y(item.end);
      lines.appendChild(svg('line', {x1, y1, x2, y2, stroke: item.color, 'stroke-width': 3.5, 'stroke-linecap': 'round'}));
      for (const [x, yy] of [[x1,y1],[x2,y2]]) {
        lines.appendChild(svg('circle', {cx: x, cy: yy, r: 5, fill: item.color, stroke: '#F7F7F4', 'stroke-width': 1.5}));
      }
      const labelY = y2 + (near ? item.dy : -8);
      if (near) lines.appendChild(svg('line', {x1: x2+6, y1: y2, x2: x2+27, y2: labelY-3, stroke: item.color, 'stroke-width': 1}));
      lines.appendChild(svg('text', {x: 574, y: labelY, fill: item.color, 'font-size': 14, 'font-weight': 600}, `${item.name} · ${fmt.format(item.end)}`));
    }
    set('plot-desc', `Séries fictícias: candidato A: ${fmt.format(data.a1)} no primeiro turno e ${fmt.format(data.a2)} no segundo; candidato B: ${fmt.format(data.b1)} e ${fmt.format(data.b2)}.`);
  }

  function applyCity(key) {
    const data = mockCities[key];
    if (!data) return;
    const da = data.a2 - data.a1;
    const db = data.b2 - data.b1;
    const dt = data.turnout2 - data.turnout1;
    const di = data.invalid2 - data.invalid1;
    const rhs = data.others + dt - di;
    if (rhs !== da + db) throw new Error('Fixture inconsistente: identidade contábil não fecha.');
    set('breadcrumb-city', data.short);
    set('city-title', data.name);
    set('coverage', `${fmt.format(data.sections)} de ${fmt.format(data.sections)} seções comparáveis (simulação)`);
    set('chart-a1', fmt.format(data.a1));
    set('chart-a2', fmt.format(data.a2));
    set('chart-b1', fmt.format(data.b1));
    set('chart-b2', fmt.format(data.b2));
    set('metric-a', fmt.format(data.a2));
    set('metric-a-delta', `${signed(da)} votos ante o 1º turno`);
    set('metric-b', fmt.format(data.b2));
    set('metric-b-delta', `${signed(db)} votos ante o 1º turno`);
    set('metric-turnout', signed(dt));
    set('metric-invalid', signed(di));
    set('eq-others', fmt.format(data.others));
    set('eq-turnout', signed(dt));
    set('eq-invalid', signed(-di));
    set('eq-result', fmt.format(da+db));
    updateChart(data);
  }

  const tabs = [...document.querySelectorAll('[role="tab"]')];
  function activateTab(tab, focus = false) {
    tabs.forEach(button => {
      const selected = button === tab;
      button.classList.toggle('active', selected);
      button.setAttribute('aria-selected', String(selected));
      button.tabIndex = selected ? 0 : -1;
      const panel = get('panel-' + button.dataset.tab);
      if (panel) panel.hidden = !selected;
    });
    if (focus) tab.focus();
  }
  tabs.forEach((tab, idx) => {
    tab.addEventListener('click', () => activateTab(tab));
    tab.addEventListener('keydown', evt => {
      let target;
      if (evt.key === 'ArrowRight') target = tabs[(idx+1) % tabs.length];
      if (evt.key === 'ArrowLeft') target = tabs[(idx-1+tabs.length) % tabs.length];
      if (evt.key === 'Home') target = tabs[0];
      if (evt.key === 'End') target = tabs[tabs.length-1];
      if (target) { evt.preventDefault(); activateTab(target, true); }
    });
  });
  get('city').addEventListener('change', evt => applyCity(evt.target.value));
  applyCity('modelo');
})();

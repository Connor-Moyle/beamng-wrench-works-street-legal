// Car theft: the screens' data contract as a fixture (docs/THEFT_CONTRACT.md): what sl_theft hands the three mini-game screens through guihooks
// 'slTheftGame', one spec per stage kind, and the summary the phone's Hot cars list reads. The screens' tests and sl_theft's own test read it.
module.exports = {
  lock: { vid: 1234, stage: 'lock', stages: ['lock', 'wires'], era: 'old', tool: null, model: 'covet', name: 'Ibishu Covet DX', noise: 0,
    difficulty: { era: 'old', prestige: false, stages: ['lock', 'wires'], seconds: 25, chance: 0.85, pins: 4, wires: 5, cut: 3 } },
  box: { vid: 1235, stage: 'box', stages: ['lock', 'box', 'wires'], era: 'mid', tool: 'bypass', model: 'pessima', name: 'Ibishu Pessima', noise: 0.12,
    difficulty: { era: 'mid', prestige: false, stages: ['lock', 'box', 'wires'], seconds: 40, chance: 0.7, pins: 6, wires: 7, cut: 3 } },
  wires: { vid: 1235, stage: 'wires', stages: ['lock', 'box', 'wires'], era: 'mid', tool: 'bypass', model: 'pessima', name: 'Ibishu Pessima', noise: 0.12,
    difficulty: { era: 'mid', prestige: false, stages: ['lock', 'box', 'wires'], seconds: 40, chance: 0.7, pins: 6, wires: 7, cut: 3 } },
  fob: { vid: 1236, stage: 'fob', stages: ['fob'], era: 'modern', tool: 'relay', model: 'scintilla', name: 'Civetta Scintilla', noise: 0,
    difficulty: { era: 'modern', prestige: true, stages: ['fob'], seconds: 75, chance: 0.4, windows: 1, sliders: 3 } },
  summary: { hot: [{ index: 1, name: 'Ibishu Covet DX', model: 'covet', era: 'old', value: 8000, plated: false, wanted: true, driving: true, sell: 2720, strip: 3200, plates: 1200, title: 2300 }],
    tools: [{ id: 'bypass', title: 'Bypass box', uses: 9 }], deliveries: 1, breakingIn: false },
};

import {
  describe, it, expect,
} from 'vitest';
import printMessage from '../../services/utils/print-message';

/**
 * The start-up banner.
 *
 * The art is generated from the product name and the box is sized from the
 * widest line it contains, so a longer name cannot leave the art spelling the
 * old product or push the right-hand wall out of line (both were real defects).
 */

const strip = (text) => text.replace(/\x1b\[[0-9;]*m/g, '');

/* Terminal columns: the banner carries one emoji, which occupies two. */
const WIDE = /[\u{1F300}-\u{1FAFF}]/u;
const width = (line) => [...line].reduce((w, ch) => w + (WIDE.test(ch) ? 2 : 1), 0);

const boxLines = (rendered) => strip(rendered)
  .split('\n')
  .filter((line) => /^[┏┃┗]/.test(line));

describe('the start-up banner', () => {
  it('spells the product name, never the upstream one', () => {
    const rendered = strip(printMessage('0.0.0.0', 4180, false));
    expect(rendered).not.toMatch(/dashy/i);
    const artRows = rendered.split('\n').filter((line) => /^[█ ]+$/.test(line) && line.includes('█'));
    expect(artRows).toHaveLength(5);
    /* Ten glyphs, five columns each with one column between them. Every glyph
       cell must be drawn, and nothing may follow the tenth. */
    for (let letter = 0; letter < 10; letter += 1) {
      const cell = artRows.map((row) => row.slice(letter * 6, (letter * 6) + 5));
      expect(cell.some((row) => row.includes('█')), `glyph ${letter + 1} is empty`).toBe(true);
    }
    expect(artRows.some((row) => (row.slice(60) || '').includes('█'))).toBe(false);
  });

  it('names the product and the address it is serving', () => {
    const rendered = strip(printMessage('0.0.0.0', 4180, false));
    expect(rendered).toContain('Welcome to Workcenter!');
    expect(rendered).toContain('http://0.0.0.0:4180');
    expect(rendered).not.toContain('undefined');
  });

  it('draws every box line at the same width', () => {
    [printMessage('0.0.0.0', 4180, false),
      printMessage('workcenter.internal.example.com', 4180, false),
      printMessage('::1', 8080, false)].forEach((rendered) => {
      const lines = boxLines(rendered);
      expect(lines.length).toBeGreaterThanOrEqual(4);
      const widths = new Set(lines.map(width));
      expect(widths.size).toBe(1);
    });
  });

  it('keeps the art and the box aligned when the address is long', () => {
    const rendered = strip(printMessage('a-very-long-hostname.internal.example.com', 4180, false));
    const artWidth = Math.max(...rendered.split('\n')
      .filter((line) => /^[█ ]+$/.test(line) && line.includes('█'))
      .map((line) => width(line)));
    const innerWidth = width(boxLines(rendered)[0]) - 2;
    expect(artWidth).toBeLessThanOrEqual(innerWidth);
  });

  it('renders the container variant with its own wording', () => {
    const rendered = strip(printMessage('0.0.0.0', 4180, true));
    expect(rendered).toContain('Welcome to Workcenter!');
    expect(rendered).toMatch(/with Docker|container ID/);
    expect(rendered).not.toMatch(/dashy/i);
  });
});

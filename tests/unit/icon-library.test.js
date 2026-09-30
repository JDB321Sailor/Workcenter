import {
  describe, it, expect, beforeEach,
} from 'vitest';
import HomeMixin from '@/mixins/HomeMixin';

/**
 * The shell's chrome renders font icons — sidebar rows, the pane overflow menu,
 * the preference controls — so the library has to be requested even though no
 * tile section asks for it. It was not, and every one of those glyphs was blank.
 */
describe('the shell’s icon library', () => {
  const context = (appConfig) => ({ appConfig, ...HomeMixin.methods });

  beforeEach(() => {
    document.head.innerHTML = '';
  });

  it('is needed whenever the deployment has not turned it off', () => {
    expect(HomeMixin.methods.checkIfFontAwesomeNeeded.call(context({}))).toBe(true);
    expect(HomeMixin.methods.checkIfFontAwesomeNeeded.call(context({ theme: 'default' }))).toBe(true);
  });

  it('honours an explicit opt-out', () => {
    expect(HomeMixin.methods.checkIfFontAwesomeNeeded.call(
      context({ enableFontAwesome: false }),
    )).toBe(false);
  });

  it('asks the browser for the kit it is configured with', () => {
    HomeMixin.methods.initiateFontAwesome.call(context({ fontAwesomeKey: 'test-key' }));
    const script = document.head.querySelector('script[src]');
    expect(script).not.toBeNull();
    expect(script.getAttribute('src')).toBe('https://kit.fontawesome.com/test-key.js');
  });

  it('adds nothing when the deployment turned it off', () => {
    HomeMixin.methods.initiateFontAwesome.call(context({ enableFontAwesome: false }));
    expect(document.head.querySelector('script[src]')).toBeNull();
  });
});

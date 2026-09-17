import {
  describe, it, expect, beforeEach, afterEach, vi,
} from 'vitest';
import { resolveField, formatValue, adaptiveColor } from '@/utils/CustomApiHelpers';

describe('CustomApiHelpers - resolveField', () => {
  it('resolves a nested dot-path', () => {
    expect(resolveField({ a: { b: 1 } }, 'a.b')).toBe(1);
  });

  it('resolves array indices in the path', () => {
    expect(resolveField({ a: [{ n: 'x' }] }, 'a.0.n')).toBe('x');
  });

  it('returns undefined for a missing path without throwing', () => {
    expect(resolveField({ a: 1 }, 'a.b.c')).toBeUndefined();
  });

  it('returns the root when path is omitted', () => {
    expect(resolveField('scalar')).toBe('scalar');
  });

  it('returns null when the object is null', () => {
    expect(resolveField(null, 'a')).toBeNull();
  });
});

describe('CustomApiHelpers - formatValue', () => {
  it('text: null becomes an empty string', () => {
    expect(formatValue(null, { format: 'text' })).toBe('');
  });

  it('text: coerces to string', () => {
    expect(formatValue(5, { format: 'text' })).toBe('5');
  });

  it('number: formats with grouping', () => {
    expect(formatValue(1234, { format: 'number', locale: 'en-US' })).toBe('1,234');
  });

  it('number: passes through non-numeric input', () => {
    expect(formatValue('abc', { format: 'number', locale: 'en-US' })).toBe('abc');
  });

  it('float: is an alias of number', () => {
    expect(formatValue(1234.5, { format: 'float', locale: 'en-US' })).toBe('1,234.5');
  });

  it('percent: treats the value as an already-computed percentage', () => {
    expect(formatValue(42, { format: 'percent', locale: 'en-US' })).toBe('42%');
  });

  it('date: formats a valid date', () => {
    const out = formatValue('2026-06-10', { format: 'date', dateStyle: 'long', locale: 'en-US' });
    expect(out).toMatch(/2026/);
  });

  it('date: passes through an invalid date', () => {
    expect(formatValue('notadate', { format: 'date', locale: 'en-US' })).toBe('notadate');
  });

  it('size: counts array elements (root when field omitted)', () => {
    expect(formatValue([1, 2, 3], { format: 'size' }, [1, 2, 3])).toBe('3');
  });

  it('size: counts object keys', () => {
    expect(formatValue({ a: 1, b: 2 }, { format: 'size' }, { a: 1, b: 2 })).toBe('2');
  });

  it('bytes: auto-selects a readable unit', () => {
    expect(formatValue(1073741824, { format: 'bytes' })).toBe('1 GB');
  });

  it('bytes: passes through non-numeric input', () => {
    expect(formatValue('abc', { format: 'bytes' })).toBe('abc');
  });

  it('bytes: handles zero, fractional and negative values', () => {
    expect(formatValue(0, { format: 'bytes' })).toBe('0 Bytes');
    expect(formatValue(0.5, { format: 'bytes' })).toBe('0.5 Bytes');
    expect(formatValue(-1073741824, { format: 'bytes' })).toBe('-1 GB');
  });

  it('bitrate: auto-selects a readable unit', () => {
    expect(formatValue(2500000, { format: 'bitrate' })).toBe('2.5 Mbps');
  });

  it('duration: shows seconds as a compact time', () => {
    expect(formatValue(93784, { format: 'duration' })).toBe('1d 2h');
    expect(formatValue(330, { format: 'duration' })).toBe('5m 30s');
    expect(formatValue(0, { format: 'duration' })).toBe('0s');
  });

  it('duration: passes through non-numeric input', () => {
    expect(formatValue('abc', { format: 'duration' })).toBe('abc');
  });

  it('remap: swaps a matching value', () => {
    const remap = [{ value: 0, to: 'Down' }, { value: 1, to: 'Up' }];
    expect(formatValue(1, { format: 'text', remap })).toBe('Up');
    expect(formatValue('1', { format: 'text', remap })).toBe('Up');
  });

  it('remap: `any` acts as a catch-all', () => {
    const remap = [{ value: 0, to: 'Down' }, { any: true, to: 'Unknown' }];
    expect(formatValue(7, { format: 'text', remap })).toBe('Unknown');
  });

  it('remap: leaves unmatched values alone', () => {
    expect(formatValue(7, { format: 'text', remap: [{ value: 0, to: 'Down' }] })).toBe('7');
  });

  it('scale: multiplies by a numeric factor before formatting', () => {
    expect(formatValue(2, { format: 'number', scale: 1024, locale: 'en-US' })).toBe('2,048');
  });

  it('scale: accepts a fraction string', () => {
    expect(formatValue(32, { format: 'number', scale: '1/16', locale: 'en-US' })).toBe('2');
  });

  it('scale: ignores an invalid factor', () => {
    expect(formatValue(5, { format: 'number', scale: 'abc', locale: 'en-US' })).toBe('5');
    expect(formatValue(5, { format: 'number', scale: '1/0', locale: 'en-US' })).toBe('5');
  });

  it('prefix and suffix wrap the formatted value', () => {
    expect(formatValue(42, { format: 'number', prefix: '$', suffix: ' USD', locale: 'en-US' })).toBe('$42 USD');
  });

  it('prefix/suffix are skipped when the value is empty', () => {
    expect(formatValue(null, { format: 'text', suffix: ' TB' })).toBe('');
  });
});

describe('CustomApiHelpers - adaptiveColor', () => {
  it('returns success for a positive value', () => {
    expect(adaptiveColor(5)).toBe('success');
  });
  it('returns error for a negative value', () => {
    expect(adaptiveColor(-2.4)).toBe('error');
  });
  it('returns info for zero', () => {
    expect(adaptiveColor(0)).toBe('info');
  });
  it('returns no colour for non-numeric input', () => {
    expect(adaptiveColor('online')).toBe('');
  });
});

describe('CustomApiHelpers - relativeDate', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-06-10T00:00:00Z'));
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  it('formats a past date', () => {
    const out = formatValue('2026-06-08T00:00:00Z', { format: 'relativeDate', locale: 'en-US' });
    expect(out).toBe('2 days ago');
  });

  it('formats a future date', () => {
    const out = formatValue('2026-06-13T00:00:00Z', { format: 'relativeDate', locale: 'en-US' });
    expect(out).toBe('in 3 days');
  });
});

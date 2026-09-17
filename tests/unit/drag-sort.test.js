import { describe, it, expect } from 'vitest';
import { reorder } from '@/directives/DragSort';
import { applyItemId, stripItemIds } from '@/utils/config/SectionHelpers';

describe('DragSort - reorder', () => {
  it('moves an element forwards', () => {
    expect(reorder(['a', 'b', 'c', 'd'], 0, 2)).toEqual(['b', 'c', 'a', 'd']);
  });

  it('moves an element backwards', () => {
    expect(reorder(['a', 'b', 'c', 'd'], 3, 1)).toEqual(['a', 'd', 'b', 'c']);
  });

  it('returns a new array, without mutating the input', () => {
    const input = ['a', 'b', 'c'];
    const result = reorder(input, 0, 1);
    expect(result).not.toBe(input);
    expect(input).toEqual(['a', 'b', 'c']);
  });
});

describe('SectionHelpers - stripItemIds', () => {
  const sections = [{
    name: 'Section One',
    items: [{ title: 'Item A', url: 'https://a.example' }],
    widgets: [{ type: 'clock', options: { label: 'Time' } }],
  }];

  it('removes runtime ids added by applyItemId', () => {
    expect(stripItemIds(applyItemId(sections))).toEqual(sections);
  });

  it('leaves sections without items or widgets untouched', () => {
    expect(stripItemIds([{ name: 'Empty' }])).toEqual([{ name: 'Empty' }]);
  });

  it('handles nullish input', () => {
    expect(stripItemIds(null)).toEqual([]);
  });
});

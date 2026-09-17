/* Directive for drag-and-drop sorting of lists, using SortableJS.
 * Applied to a list container, with options: { enabled, onSorted, draggable, handle, group,
 * filter, meta }. On drop, Sortable's DOM change is reverted (Vue owns the DOM), then
 * `onSorted({ oldIndex, newIndex, from, to })` is called with each container's `meta`,
 * so the caller can commit the move to the store and let Vue re-render */
import { Sortable } from 'sortablejs';
import ErrorHandler from '@/utils/logging/ErrorHandler';

const ACTIVE_CLASS = 'drag-sort-active';
const registry = new WeakMap(); // container element -> { sortable, meta }

/* Returns a copy of an array, with one element moved to a new index */
export const reorder = (arr, fromIndex, toIndex) => {
  const result = [...arr];
  result.splice(toIndex, 0, ...result.splice(fromIndex, 1));
  return result;
};

const createSortable = (el, options) => {
  const { draggable, handle, group, filter, onSorted } = options;
  // The dragged element's original next sibling, for DOM revert. May be a text node:
  // v-for fragments are unmounted by anchor range, so the revert must land inside it
  let anchor = null;
  return new Sortable(el, {
    draggable,
    handle,
    group,
    filter,
    preventOnFilter: false,
    animation: 150,
    delay: 150,
    delayOnTouchOnly: true,
    forceFallback: true, // Consistent ghost behaviour, and no native link-drag on anchors
    fallbackTolerance: 3,
    ghostClass: 'drag-sort-ghost',
    // Prevent dropping after non-sortable trailing elements (e.g. add-new launchers),
    // except into lists with no sortable children yet
    onMove: (e) => !e.related || e.related.matches(draggable) || !e.willInsertAfter
      || !e.to.querySelector(draggable),
    onStart: (e) => { anchor = e.item.nextSibling; },
    onEnd: (e) => {
      const { item, from, to, oldIndex, newIndex } = e;
      from.insertBefore(item, anchor);
      if (from === to && oldIndex === newIndex) return;
      try {
        onSorted({
          oldIndex,
          newIndex,
          from: registry.get(from)?.meta,
          to: registry.get(to)?.meta,
        });
      } catch (error) {
        ErrorHandler('Failed to apply drag-and-drop reorder', error);
      }
    },
  });
};

const sync = (el, options = {}) => {
  const entry = registry.get(el) || {};
  entry.meta = options.meta;
  registry.set(el, entry);
  if (options.enabled && !entry.sortable) {
    entry.sortable = createSortable(el, options);
  } else if (!options.enabled && entry.sortable) {
    entry.sortable.destroy();
    entry.sortable = null;
  }
  // Re-applied on every update, as Vue class patching may remove it
  el.classList.toggle(ACTIVE_CLASS, !!entry.sortable);
};

const destroy = (el) => {
  registry.get(el)?.sortable?.destroy();
  registry.delete(el);
};

export default {
  mounted: (el, binding) => sync(el, binding.value),
  updated: (el, binding) => sync(el, binding.value),
  unmounted: destroy,
};

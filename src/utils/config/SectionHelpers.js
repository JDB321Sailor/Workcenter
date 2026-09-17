/* Helper functions for Sections and Items */

import { hideFurnitureOn } from '@/utils/config/defaults';

/* Returns false if page furniture should be hidden on said route */
export const shouldBeVisible = (routeName) => {
  let shouldShow = true;
  if (!routeName) return shouldShow; // Route name not specified.
  hideFurnitureOn.forEach((hideOn) => {
    // If route name on the no-show list, set visibility to false
    if (routeName.includes(hideOn)) shouldShow = false;
  });
  return shouldShow;
};

/* Based on section title, item name and index, return a string value for ID */
const makeItemId = (sectionStr, itemStr, index) => {
  const sectionTitle = String(sectionStr || `unlabeledSec_${Math.random()}`);
  const charSum = sectionTitle.split('').map((a) => a.charCodeAt(0)).reduce((x, y) => x + y);
  const newItemStr = String(itemStr || `unknown_${Math.random()}`);
  const itemTitleStr = newItemStr.replace(/\s+/g, '-').replace(/[^a-zA-Z ]/g, '').toLowerCase();
  return `${index}_${charSum}_${itemTitleStr}`;
};

/* Return a new array of sections, without item/widget ids so they don't get saved */
export const stripItemIds = (inputSections) => (inputSections || []).map((section) => {
  const next = { ...section };
  if (Array.isArray(section.items)) {
    next.items = section.items.map(({ id: _id, ...item }) => item);
  }
  if (Array.isArray(section.widgets)) {
    next.widgets = section.widgets.map(({ id: _id, ...widget }) => widget);
  }
  return next;
});

/* Return a new array of sections with a unique id on each item and widget */
export const applyItemId = (inputSections) => (inputSections || []).map((section) => {
  const next = { ...section };
  if (Array.isArray(section.items)) {
    next.items = section.items.map((item, i) => ({
      ...item,
      id: makeItemId(section.name, item.title, i),
    }));
  }
  if (Array.isArray(section.widgets)) {
    next.widgets = section.widgets.map((widget, i) => ({
      ...widget,
      id: makeItemId(section.name, widget.type, i),
    }));
  }
  return next;
});

/* Returns new sections array, with the `transform` function applied to section with given `name` */
export const mapSectionByName = (sections, name, transform) => (
  sections.map((section) => ((section.name || '') === name ? transform(section) : section))
);

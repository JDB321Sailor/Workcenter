/* Field resolution and value formatting for the CustomApi widget */
import { convertBytes, convertBitrate, convertDuration } from '@/utils/MiscHelpers';

/* Get a nested value from an object by dot-path, e.g. 'a.b.0.c'. Empty path returns the root */
export const resolveField = (obj, path) => {
  if (!path) return obj;
  return String(path).split('.').reduce((acc, key) => (acc == null ? acc : acc[key]), obj);
};

/* Map a value's sign to an action colour, for `color: adaptive` fields. Non-numeric stays neutral */
export const adaptiveColor = (raw) => {
  const n = Number(raw);
  if (Number.isNaN(n)) return '';
  if (n > 0) return 'success';
  if (n < 0) return 'error';
  return 'info';
};

/* Largest-first periods, used to pick a unit for relative dates */
const RELATIVE_UNITS = [
  { unit: 'year', secs: 31557600 },
  { unit: 'month', secs: 2628000 },
  { unit: 'week', secs: 604800 },
  { unit: 'day', secs: 86400 },
  { unit: 'hour', secs: 3600 },
  { unit: 'minute', secs: 60 },
  { unit: 'second', secs: 1 },
];

/* Format a date as relative to now, e.g. '2 days ago' or 'in 3 hours' */
const formatRelativeDate = (raw, mapping, locale) => {
  const time = new Date(raw).getTime();
  if (Number.isNaN(time)) return String(raw);
  const diffSecs = (time - Date.now()) / 1000;
  const period = RELATIVE_UNITS.find((p) => Math.abs(diffSecs) >= p.secs)
    || RELATIVE_UNITS[RELATIVE_UNITS.length - 1];
  const rtf = new Intl.RelativeTimeFormat(locale, {
    style: mapping.style || 'long',
    numeric: mapping.numeric || 'always',
  });
  return rtf.format(Math.round(diffSecs / period.secs), period.unit);
};

/* Multiply a numeric value by a mapping's `scale` — a number or fraction string like '1/16' */
const applyScale = (raw, scale) => {
  if (!scale) return raw;
  const n = Number(raw);
  const [top, bottom = 1] = String(scale).split('/').map(Number);
  const factor = top / bottom;
  return (Number.isNaN(n) || !Number.isFinite(factor)) ? raw : n * factor;
};

/* Swap a value for a matching remap entry's `to`, e.g. 0 → 'Down'. `any: true` matches all */
const applyRemap = (raw, remaps) => {
  if (!Array.isArray(remaps)) return raw;
  const match = remaps.find((r) => r && r.to !== undefined && (r.any || String(r.value) === String(raw)));
  return match ? match.to : raw;
};

/* Format a raw value per a mapping's `format`. `root` is the full response, used by `size` */
const applyFormat = (raw, mapping, root) => {
  const format = mapping.format || 'text';
  const locale = mapping.locale || navigator.language;

  // `size` counts array elements / object keys (root when no field is given)
  if (format === 'size') {
    const target = mapping.field == null ? root : raw;
    if (Array.isArray(target)) return String(target.length);
    if (target && typeof target === 'object') return String(Object.keys(target).length);
    return target == null ? '' : String(target);
  }

  if (raw == null) return '';
  const value = applyScale(applyRemap(raw, mapping.remap), mapping.scale);

  switch (format) {
    case 'number':
    case 'float': {
      const n = Number(value);
      return Number.isNaN(n) ? String(value) : new Intl.NumberFormat(locale).format(n);
    }
    case 'percent': {
      const n = Number(value);
      return Number.isNaN(n) ? String(value)
        : new Intl.NumberFormat(locale, { style: 'percent', maximumFractionDigits: 2 }).format(n / 100);
    }
    case 'bytes':
    case 'bitrate': {
      const n = Number(value);
      if (Number.isNaN(n)) return String(value);
      return format === 'bytes' ? convertBytes(n) : convertBitrate(n);
    }
    case 'duration': {
      const n = Number(value);
      return Number.isNaN(n) ? String(value) : convertDuration(n);
    }
    case 'date': {
      const date = new Date(value);
      if (Number.isNaN(date.getTime())) return String(value);
      const opts = { dateStyle: mapping.dateStyle || 'long' };
      if (mapping.timeStyle) opts.timeStyle = mapping.timeStyle;
      return new Intl.DateTimeFormat(locale, opts).format(date);
    }
    case 'relativeDate':
      return formatRelativeDate(value, mapping, locale);
    default:
      return String(value);
  }
};

/* Formatted value, wrapped with any `prefix`/`suffix` */
export const formatValue = (raw, mapping = {}, root) => {
  const out = applyFormat(raw, mapping, root);
  return out === '' ? out : `${mapping.prefix || ''}${out}${mapping.suffix || ''}`;
};

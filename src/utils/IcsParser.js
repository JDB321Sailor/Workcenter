/**
 * Attempt at a minimal iCal parser, following RFC 5545
 * Returning a time-ordered list of events from requested start date
 * Used for the calendar widget
 */

const DAYS = ['SU', 'MO', 'TU', 'WE', 'TH', 'FR', 'SA'];
const FREQS = ['DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY'];
const DAY_MS = 86400000;
// Longest each period can be, so skipping ahead always lands early, never past an occurrence
const PERIOD_MS = {
  DAILY: DAY_MS, WEEKLY: 7 * DAY_MS, MONTHLY: 31 * DAY_MS, YEARLY: 366 * DAY_MS,
};
const MAX_PERIODS = 5000;
const LOCAL_ZONE = Intl.DateTimeFormat().resolvedOptions().timeZone;

const TEXT_FIELDS = {
  UID: 'uid',
  SUMMARY: 'summary',
  DESCRIPTION: 'description',
  LOCATION: 'location',
  URL: 'url',
  STATUS: 'status',
};

/* Undo RFC 5545 line folding, and split into logical lines */
const unfold = (text) => text
  .replace(/^\uFEFF/, '')
  .replace(/\r\n|\r/g, '\n')
  .replace(/\n[ \t]/g, '')
  .split('\n');

/* Split `NAME;PARAM=VALUE:value` into its parts, ignoring colons inside quotes */
const parseLine = (line) => {
  let quoted = false;
  for (let i = 0; i < line.length; i += 1) {
    if (line[i] === '"') quoted = !quoted;
    else if (line[i] === ':' && !quoted) {
      const [name, ...rest] = line.slice(0, i).split(';');
      const params = {};
      rest.forEach((param) => {
        const eq = param.indexOf('=');
        if (eq > 0) params[param.slice(0, eq).toUpperCase()] = param.slice(eq + 1).replace(/"/g, '');
      });
      return { name: name.toUpperCase(), params, value: line.slice(i + 1) };
    }
  }
  return null;
};

const unescapeText = (value) => value.replace(/\\n/gi, '\n').replace(/\\(.)/g, '$1');

/* Named zones we can't resolve (such as Windows TZIDs) fall back to the local zone */
const zones = new Map();
const resolveZone = (tz) => {
  if (!tz) return LOCAL_ZONE;
  if (!zones.has(tz)) {
    try {
      Intl.DateTimeFormat('en-GB', { timeZone: tz });
      zones.set(tz, tz);
    } catch {
      zones.set(tz, LOCAL_ZONE);
    }
  }
  return zones.get(tz);
};

/* How far the given zone is from UTC, at the given moment */
const offsetAt = (ms, zone) => {
  const parts = {};
  Intl.DateTimeFormat('en-GB', {
    timeZone: zone,
    hourCycle: 'h23',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  }).formatToParts(ms).forEach(({ type, value }) => { parts[type] = value; });
  return Date.UTC(parts.year, parts.month - 1, parts.day, parts.hour, parts.minute, parts.second) - ms;
};

/* Parse a date or date-time. `wall` holds the clock face, as if it were UTC */
const parseDate = (value, params = {}) => {
  const match = /^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})(Z)?)?$/.exec(value.trim());
  if (!match) return null;
  const [, year, month, day, hour, minute, second, utc] = match;
  return {
    wall: Date.UTC(year, month - 1, day, hour || 0, minute || 0, second || 0),
    zone: utc ? 'UTC' : params.TZID || null,
    allDay: !hour || params.VALUE === 'DATE',
  };
};

/* Resolve a wall-clock time in its own zone to a real timestamp */
const toEpoch = ({ wall, zone, allDay }) => {
  if (allDay || zone === 'UTC') return wall;
  const resolved = resolveZone(zone);
  return wall - offsetAt(wall - offsetAt(wall, resolved), resolved);
};

const parseDuration = (value) => {
  const [, w, d, h, m, s] = /^P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$/
    .exec(value.trim()) || [];
  return ((+w || 0) * 604800 + (+d || 0) * 86400 + (+h || 0) * 3600
    + (+m || 0) * 60 + (+s || 0)) * 1000;
};

const parseRule = (value) => {
  const rule = {};
  value.split(';').forEach((part) => {
    const [key, val] = part.split('=');
    if (val) rule[key.toUpperCase()] = val;
  });
  return rule;
};

const numbers = (value) => (value ? value.split(',').map(Number) : null);

const startOfPeriod = (ms, freq, weekStart) => {
  const date = new Date(ms);
  date.setUTCHours(0, 0, 0, 0);
  if (freq === 'WEEKLY') date.setUTCDate(date.getUTCDate() - ((date.getUTCDay() - weekStart + 7) % 7));
  if (freq === 'MONTHLY') date.setUTCDate(1);
  if (freq === 'YEARLY') date.setUTCMonth(0, 1);
  return date.getTime();
};

const addPeriods = (ms, freq, amount) => {
  const date = new Date(ms);
  if (freq === 'DAILY') date.setUTCDate(date.getUTCDate() + amount);
  if (freq === 'WEEKLY') date.setUTCDate(date.getUTCDate() + amount * 7);
  if (freq === 'MONTHLY') date.setUTCMonth(date.getUTCMonth() + amount);
  if (freq === 'YEARLY') date.setUTCFullYear(date.getUTCFullYear() + amount);
  return date.getTime();
};

/* Days in a month matching BYDAY tokens, honouring ordinals like `3TU` or `-1SU` */
const daysMatchingByDay = (byDay, monthStart, monthLength) => {
  const found = [];
  byDay.forEach((token) => {
    const nth = parseInt(token, 10) || 0;
    const weekday = DAYS.indexOf(token.slice(-2));
    const matches = [];
    for (let day = 0; day < monthLength; day += 1) {
      const ms = monthStart + day * DAY_MS;
      if (new Date(ms).getUTCDay() === weekday) matches.push(ms);
    }
    if (!nth) found.push(...matches);
    else {
      const nthMatch = matches[nth > 0 ? nth - 1 : matches.length + nth];
      if (nthMatch) found.push(nthMatch);
    }
  });
  return found;
};

/* Candidate days within a single period, before time-of-day is applied */
const daysInPeriod = (cursor, freq, rule, anchor) => {
  const { byDay, byMonth, byMonthDay } = rule;
  if (freq === 'DAILY' || freq === 'WEEKLY') {
    let weekdays = byDay && byDay.map((token) => DAYS.indexOf(token.slice(-2)));
    // A weekly rule with no BYDAY repeats on whichever day it started
    if (!weekdays && freq === 'WEEKLY') weekdays = [new Date(anchor).getUTCDay()];
    const span = freq === 'DAILY' ? 1 : 7;
    const days = [];
    for (let day = 0; day < span; day += 1) {
      const ms = cursor + day * DAY_MS;
      if (!weekdays || weekdays.includes(new Date(ms).getUTCDay())) days.push(ms);
    }
    return days;
  }
  const year = new Date(cursor).getUTCFullYear();
  const months = freq === 'YEARLY'
    ? (byMonth || [new Date(anchor).getUTCMonth() + 1])
    : [new Date(cursor).getUTCMonth() + 1];
  const days = [];
  months.forEach((month) => {
    const monthStart = Date.UTC(year, month - 1, 1);
    const monthLength = new Date(Date.UTC(year, month, 0)).getUTCDate();
    if (byDay) {
      days.push(...daysMatchingByDay(byDay, monthStart, monthLength));
    } else {
      const wanted = byMonthDay || [new Date(anchor).getUTCDate()];
      wanted.forEach((day) => {
        const resolved = day > 0 ? day : monthLength + day + 1;
        if (resolved >= 1 && resolved <= monthLength) {
          days.push(monthStart + (resolved - 1) * DAY_MS);
        }
      });
    }
  });
  return days;
};

/* Walk a recurrence rule, collecting occurrence start times as wall values */
const expandRule = (rule, start, range) => {
  const freq = rule.FREQ;
  if (!FREQS.includes(freq)) return [start.wall];
  const interval = parseInt(rule.INTERVAL, 10) || 1;
  const count = parseInt(rule.COUNT, 10) || 0;
  const until = rule.UNTIL ? toEpoch(parseDate(rule.UNTIL)) : null;
  const parsed = {
    byDay: rule.BYDAY ? rule.BYDAY.split(',') : null,
    byMonthDay: numbers(rule.BYMONTHDAY),
    byMonth: numbers(rule.BYMONTH),
  };
  const bySetPos = numbers(rule.BYSETPOS);
  const weekStart = DAYS.includes(rule.WKST) ? DAYS.indexOf(rule.WKST) : 1;
  const timeOfDay = ((start.wall % DAY_MS) + DAY_MS) % DAY_MS;

  let cursor = startOfPeriod(start.wall, freq, weekStart);
  // Skip the periods before our window, unless COUNT means they all matter
  if (!count && cursor < range.start) {
    const skip = Math.floor((range.start - cursor) / (PERIOD_MS[freq] * interval)) - 1;
    if (skip > 0) cursor = addPeriods(cursor, freq, skip * interval);
  }

  const found = [];
  for (let period = 0; period < MAX_PERIODS && cursor <= range.end; period += 1) {
    let days = daysInPeriod(cursor, freq, parsed, start.wall);
    if (parsed.byMonth && freq !== 'YEARLY') {
      days = days.filter((ms) => parsed.byMonth.includes(new Date(ms).getUTCMonth() + 1));
    }
    let candidates = days.map((ms) => ms + timeOfDay).sort((a, b) => a - b);
    if (bySetPos) {
      candidates = bySetPos
        .map((pos) => candidates[pos > 0 ? pos - 1 : candidates.length + pos])
        .filter((ms) => ms !== undefined);
    }
    for (const wall of candidates) {
      if (wall >= start.wall) {
        if (until !== null && toEpoch({ ...start, wall }) > until) return found;
        found.push(wall);
        if (count && found.length >= count) return found;
      }
    }
    cursor = addPeriods(cursor, freq, interval);
  }
  return found;
};

/* Read the calendar's name and every VEVENT, skipping nested parts such as VALARM */
const readCalendar = (text) => {
  const events = [];
  let calendarName = '';
  let event = null;
  let nested = 0;
  unfold(text).forEach((raw) => {
    const line = parseLine(raw);
    if (!line) return;
    const { name, params, value } = line;
    if (name === 'BEGIN') {
      if (value === 'VEVENT' && !event) event = { exdates: [], rdates: [] };
      else if (event) nested += 1;
      return;
    }
    if (name === 'END') {
      if (nested) nested -= 1;
      else if (value === 'VEVENT' && event) { events.push(event); event = null; }
      return;
    }
    if (!event) {
      if (name === 'X-WR-CALNAME') calendarName = unescapeText(value);
      return;
    }
    if (nested) return;
    if (TEXT_FIELDS[name]) event[TEXT_FIELDS[name]] = unescapeText(value);
    else if (name === 'DTSTART') event.start = parseDate(value, params);
    else if (name === 'DTEND') event.end = parseDate(value, params);
    else if (name === 'DURATION') event.duration = parseDuration(value);
    else if (name === 'RRULE') event.rrule = parseRule(value);
    else if (name === 'RECURRENCE-ID') event.recurrenceId = parseDate(value, params);
    else if (name === 'EXDATE' || name === 'RDATE') {
      const target = name === 'EXDATE' ? event.exdates : event.rdates;
      value.split(',').forEach((part) => {
        const date = parseDate(part, params);
        if (date) target.push(date.wall);
      });
    }
  });
  return { name: calendarName, events };
};

/* Turn one occurrence into the flat shape the widget renders */
const buildOccurrence = (event, wall) => {
  const start = toEpoch({ ...event.start, wall });
  let end = start;
  if (event.end) end = toEpoch({ ...event.end, wall: wall + (event.end.wall - event.start.wall) });
  else if (event.duration) end = start + event.duration;
  return {
    uid: event.uid,
    summary: event.summary || '',
    description: event.description || '',
    location: event.location || '',
    url: event.url || '',
    allDay: event.start.allDay,
    start,
    end,
  };
};

const isCancelled = (event) => event.status === 'CANCELLED';

/**
 * Parse an ICS document into the occurrences falling within `range`.
 * @param {string} text - Raw iCalendar document
 * @param {{ start: number, end: number }} range - Window, as epoch milliseconds
 * @returns {{ name: string, events: Array }} Feed name, and occurrences ordered by start time
 */
export const parseIcs = (text, range) => {
  if (!text || typeof text !== 'string' || !text.includes('BEGIN:VCALENDAR')) {
    throw new Error('Not a valid iCalendar feed');
  }
  const { name, events } = readCalendar(text);
  const overrides = new Map();
  events.forEach((event) => {
    if (event.recurrenceId && event.uid) {
      overrides.set(`${event.uid}|${event.recurrenceId.wall}`, event);
    }
  });

  /* Anything overlapping the window, so events stay listed while they are still running */
  const inRange = ({ start, end }) => start <= range.end
    && (start >= range.start || end > range.start);
  const occurrences = [];

  events.forEach((event) => {
    if (event.recurrenceId || !event.start || isCancelled(event)) return;
    const starts = event.rrule ? expandRule(event.rrule, event.start, range) : [event.start.wall];
    const all = [...new Set([...starts, ...event.rdates])];
    all.forEach((wall) => {
      if (event.exdates.includes(wall)) return;
      if (overrides.has(`${event.uid}|${wall}`)) return;
      const occurrence = buildOccurrence(event, wall);
      if (inRange(occurrence)) occurrences.push(occurrence);
    });
  });

  overrides.forEach((event) => {
    if (!event.start || isCancelled(event)) return;
    const occurrence = buildOccurrence(event, event.start.wall);
    if (inRange(occurrence)) occurrences.push(occurrence);
  });

  return { name, events: occurrences.sort((a, b) => a.start - b.start) };
};

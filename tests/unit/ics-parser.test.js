import { describe, it, expect } from 'vitest';
import { parseIcs } from '@/utils/IcsParser';

/* Wrap one or more VEVENTs, each given as a list of lines, in a minimal calendar */
const calendar = (...events) => [
  'BEGIN:VCALENDAR',
  'VERSION:2.0',
  ...events.map((lines) => ['BEGIN:VEVENT', ...lines, 'END:VEVENT'].join('\r\n')),
  'END:VCALENDAR',
].join('\r\n');

const between = (from, to) => ({
  start: Date.parse(`${from}T00:00:00Z`),
  end: Date.parse(`${to}T00:00:00Z`),
});

/* parseIcs returns the feed name alongside its events; most tests only want the events */
const parse = (ics, range) => parseIcs(ics, range).events;

const starts = (events) => events.map((event) => new Date(event.start).toISOString());
const days = (events) => events.map((event) => new Date(event.start).toISOString().slice(0, 10));
const titles = (events) => events.map((event) => event.summary);

describe('IcsParser', () => {
  it('throws on a page that is not a calendar, rather than reporting it as empty', () => {
    expect(() => parseIcs('<html>Please log in</html>', between('2026-01-01', '2026-12-31')))
      .toThrow();
  });

  it('unfolds wrapped lines and unescapes text', () => {
    const ics = calendar([
      'UID:1',
      'DTSTART:20260904T090000Z',
      'SUMMARY:Tabs vs spaces\\, the reckoning',
      'DESCRIPTION:Bring snacks\\nAnd a helmet',
      'LOCATION:The broom cupboard\\; second floor\\, past the humming server that',
      '  nobody will admit to owning',
    ]);
    const [event] = parse(ics, between('2026-09-01', '2026-09-30'));
    expect(event.summary).toBe('Tabs vs spaces, the reckoning');
    expect(event.description).toBe('Bring snacks\nAnd a helmet');
    expect(event.location)
      .toBe('The broom cupboard; second floor, past the humming server that nobody will admit to owning');
  });

  it('anchors all-day events to UTC, so the date never drifts', () => {
    const ics = calendar([
      'UID:1',
      'DTSTART;VALUE=DATE:20261225',
      'DTEND;VALUE=DATE:20261226',
      'SUMMARY:Christmas Day',
    ]);
    const [event] = parse(ics, between('2026-12-01', '2026-12-31'));
    expect(event.allDay).toBe(true);
    expect(starts([event])).toEqual(['2026-12-25T00:00:00.000Z']);
  });

  it('reads end times from either DTEND or DURATION', () => {
    const ics = calendar(
      ['UID:1', 'DTSTART:20260904T090000Z', 'DTEND:20260904T103000Z', 'SUMMARY:Long lunch'],
      ['UID:2', 'DTSTART:20260904T140000Z', 'DURATION:PT45M', 'SUMMARY:Quick chat'],
    );
    const [lunch, chat] = parse(ics, between('2026-09-01', '2026-09-30'));
    expect(lunch.end - lunch.start).toBe(90 * 60 * 1000);
    expect(chat.end - chat.start).toBe(45 * 60 * 1000);
  });

  it('holds a recurring meeting at the same local time across a DST change', () => {
    const ics = calendar([
      'UID:1',
      'DTSTART;TZID=America/New_York:20261028T090000',
      'DTEND;TZID=America/New_York:20261028T100000',
      'RRULE:FREQ=WEEKLY;BYDAY=WE',
      'SUMMARY:Weekly blameless post-mortem (mostly blame)',
    ]);
    // New York is UTC-4 on 28 Oct, but UTC-5 on 4 Nov
    expect(starts(parse(ics, between('2026-10-27', '2026-11-05'))))
      .toEqual(['2026-10-28T13:00:00.000Z', '2026-11-04T14:00:00.000Z']);
  });

  it('expands a fortnightly rule, honouring INTERVAL', () => {
    const ics = calendar([
      'UID:1',
      'DTSTART:20260907T100000Z',
      'RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=MO',
      'SUMMARY:Bin day (the good bin)',
    ]);
    expect(days(parse(ics, between('2026-09-01', '2026-10-20'))))
      .toEqual(['2026-09-07', '2026-09-21', '2026-10-05', '2026-10-19']);
  });

  it('expands ordinal BYDAY, such as the third Tuesday of the month', () => {
    const ics = calendar([
      'UID:1',
      'DTSTART:20260120T110000Z',
      'RRULE:FREQ=MONTHLY;BYDAY=3TU',
      'SUMMARY:Board game night, someone always flips the table',
    ]);
    expect(days(parse(ics, between('2026-01-01', '2026-04-01'))))
      .toEqual(['2026-01-20', '2026-02-17', '2026-03-17']);
  });

  it('expands negative BYMONTHDAY, such as the last day of the month', () => {
    const ics = calendar([
      'UID:1',
      'DTSTART:20260131T080000Z',
      'RRULE:FREQ=MONTHLY;BYMONTHDAY=-1',
      'SUMMARY:Remember what the invoices were for',
    ]);
    expect(days(parse(ics, between('2026-01-01', '2026-04-01'))))
      .toEqual(['2026-01-31', '2026-02-28', '2026-03-31']);
  });

  it('still finds occurrences of a rule that started years ago', () => {
    const ics = calendar([
      'UID:1',
      'DTSTART:20160805T170000Z',
      'RRULE:FREQ=MONTHLY;BYDAY=1WE',
      'SUMMARY:All-hands, unchanged since 2016',
    ]);
    expect(days(parse(ics, between('2026-09-03', '2026-12-03'))))
      .toEqual(['2026-10-07', '2026-11-04', '2026-12-02']);
  });

  it('applies BYSETPOS, such as the last weekday of the month', () => {
    const ics = calendar([
      'UID:1',
      'DTSTART:20260130T170000Z',
      'RRULE:FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1',
      'SUMMARY:Friday deploy, against all advice',
    ]);
    expect(days(parse(ics, between('2026-01-01', '2026-03-01'))))
      .toEqual(['2026-01-30', '2026-02-27']);
  });

  it('stops a rule at COUNT or UNTIL', () => {
    const counted = calendar([
      'UID:1', 'DTSTART:20260907T090000Z', 'RRULE:FREQ=DAILY;COUNT=3', 'SUMMARY:Three day juice cleanse',
    ]);
    expect(days(parse(counted, between('2026-09-01', '2026-10-01'))))
      .toEqual(['2026-09-07', '2026-09-08', '2026-09-09']);

    const dated = calendar([
      'UID:1', 'DTSTART:20260907T090000Z', 'RRULE:FREQ=DAILY;UNTIL=20260909T090000Z',
      'SUMMARY:Feed the neighbour\'s cat',
    ]);
    expect(days(parse(dated, between('2026-09-01', '2026-10-01'))))
      .toEqual(['2026-09-07', '2026-09-08', '2026-09-09']);
  });

  it('skips EXDATEs and adds RDATEs', () => {
    const ics = calendar([
      'UID:1',
      'DTSTART:20260907T090000Z',
      'RRULE:FREQ=DAILY;COUNT=3',
      'EXDATE:20260908T090000Z',
      'RDATE:20260912T090000Z',
      'SUMMARY:Standup, where nobody stands',
    ]);
    expect(days(parse(ics, between('2026-09-01', '2026-10-01'))))
      .toEqual(['2026-09-07', '2026-09-09', '2026-09-12']);
  });

  it('replaces a single occurrence with its RECURRENCE-ID override', () => {
    const ics = calendar(
      ['UID:1', 'DTSTART:20260907T090000Z', 'RRULE:FREQ=DAILY;COUNT=3', 'SUMMARY:Standup'],
      ['UID:1', 'RECURRENCE-ID:20260908T090000Z', 'DTSTART:20260908T160000Z',
        'SUMMARY:Standup, moved so Dave can go to the dentist'],
    );
    const events = parse(ics, between('2026-09-01', '2026-10-01'));
    expect(starts(events)).toEqual([
      '2026-09-07T09:00:00.000Z', '2026-09-08T16:00:00.000Z', '2026-09-09T09:00:00.000Z',
    ]);
    expect(events[1].summary).toContain('moved');
  });

  it('ignores cancelled events and nested components', () => {
    const ics = calendar(
      ['UID:1', 'DTSTART:20260904T090000Z', 'SUMMARY:Mandatory fun', 'STATUS:CANCELLED'],
      ['UID:2', 'DTSTART:20260904T100000Z', 'SUMMARY:Actually happening',
        'BEGIN:VALARM', 'TRIGGER:-PT10M', 'SUMMARY:Nag', 'END:VALARM'],
    );
    expect(titles(parse(ics, between('2026-09-01', '2026-09-30'))))
      .toEqual(['Actually happening']);
  });

  it('only returns events overlapping the window', () => {
    const ics = calendar(
      ['UID:1', 'DTSTART:20260801T090000Z', 'SUMMARY:Last month\'s regrets'],
      ['UID:2', 'DTSTART:20260915T090000Z', 'SUMMARY:This week\'s chaos'],
      ['UID:3', 'DTSTART:20261101T090000Z', 'SUMMARY:Next quarter\'s problem'],
    );
    expect(titles(parse(ics, between('2026-09-01', '2026-10-01'))))
      .toEqual(['This week\'s chaos']);
  });

  it('keeps an event that began before the window but has not finished', () => {
    const ics = calendar(
      ['UID:1', 'DTSTART:20260831T090000Z', 'DTEND:20260901T170000Z', 'SUMMARY:Hackathon, hour 30'],
      ['UID:2', 'DTSTART:20260831T090000Z', 'DTEND:20260831T170000Z', 'SUMMARY:Yesterday, finished'],
      ['UID:3', 'DTSTART:20260830T090000Z', 'SUMMARY:No end time, so long gone'],
    );
    expect(titles(parse(ics, between('2026-09-01', '2026-10-01'))))
      .toEqual(['Hackathon, hour 30']);
  });

  it('reads the feed name, for labelling a calendar the user has not named', () => {
    const named = `BEGIN:VCALENDAR\r\nX-WR-CALNAME:Bins\\, and when to move them\r\nEND:VCALENDAR`;
    expect(parseIcs(named, between('2026-09-01', '2026-10-01')).name)
      .toBe('Bins, and when to move them');
    expect(parseIcs(calendar(), between('2026-09-01', '2026-10-01')).name).toBe('');
  });

  it('falls back to local time for timezones it cannot resolve', () => {
    const ics = calendar([
      'UID:1',
      'DTSTART;TZID=GMT Standard Time:20260904T090000',
      'SUMMARY:Meeting booked by someone using Outlook',
    ]);
    const [event] = parse(ics, between('2026-09-01', '2026-09-30'));
    expect(new Date(event.start).getHours()).toBe(9);
  });
});

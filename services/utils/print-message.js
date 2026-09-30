/**
 * Returns a welcome message, to be printed to the user when they start the app
 * Contains essential info about restarting and managing the container or service
 *
 * The banner is generated from the product name rather than hand-drawn, and the
 * box is sized from the widest line it contains. A longer name — or a longer
 * address — therefore widens the art and the box together instead of pushing the
 * right-hand wall out of line.
 *
 * @param String ip: The users local IP address or hostname
 * @param Integer port: the port number that the app is running at
 * @param Boolean isDocker: whether or not the app is being run within a container
 * @returns A string formatted for the terminal
 */

const NAME = 'Workcenter';

/* A five-row block font, one entry per row, five columns per letter. Only the
 * letters the product name needs are defined; an unknown character renders as a
 * blank cell rather than breaking the banner. */
const FONT = {
  W: ['█   █', '█   █', '█ █ █', '██ ██', ' █ █ '],
  O: [' ███ ', '█   █', '█   █', '█   █', ' ███ '],
  R: ['████ ', '█   █', '████ ', '█  █ ', '█   █'],
  K: ['█   █', '█  █ ', '███  ', '█  █ ', '█   █'],
  C: [' ███ ', '█    ', '█    ', '█    ', ' ███ '],
  E: ['█████', '█    ', '████ ', '█    ', '█████'],
  N: ['█   █', '██  █', '█ █ █', '█  ██', '█   █'],
  T: ['█████', '  █  ', '  █  ', '  █  ', '  █  '],
};

const ROWS = 5;

/* Characters that occupy two terminal columns: the emoji this message carries.
 * Everything else it prints is single-width. */
const WIDE = /[\u1100-\u115F\u2E80-\uA4CF\uAC00-\uD7A3\uF900-\uFAFF\uFE30-\uFE6F\uFF00-\uFF60\uFFE0-\uFFE6]|[\u{1F300}-\u{1FAFF}]|[\u{2600}-\u{27BF}]/u;

const displayWidth = (text) => [...text]
  .reduce((width, char) => width + (WIDE.test(char) ? 2 : 1), 0);

/* Renders a word as rows of block letters. */
const banner = (word) => {
  const rows = new Array(ROWS).fill('');
  [...word].forEach((letter, index) => {
    const glyph = FONT[letter] || new Array(ROWS).fill('     ');
    for (let row = 0; row < ROWS; row += 1) {
      rows[row] += (index === 0 ? '' : ' ') + glyph[row];
    }
  });
  return rows;
};

module.exports = (ip, port, isDocker) => {
  const chars = { // Color codes used in the message
    RESET: '\x1b[0m',
    CYAN: '\x1b[36m',
    GREEN: '\x1b[32m',
    BLUE: '\x1b[34m',
    BRIGHT: '\x1b[1m',
    BR: '\n',
  };

  const containerId = process.env.HOST || undefined;
  const address = `http://${ip}:${port}`;
  const content = isDocker
    ? [
      `Welcome to ${NAME}! 🚀`,
      containerId
        ? `Your new dashboard is now up and running in container ID ${containerId}`
        : 'Your new dashboard is now up and running with Docker',
    ]
    : [
      `Welcome to ${NAME}! 🚀`,
      `Your new dashboard is now up and running at ${chars.BRIGHT}${address}${chars.RESET}${chars.GREEN}`,
    ];

  /* Measured separately from what is printed: colour codes take no column. */
  const measured = isDocker
    ? [`Welcome to ${NAME}! 🚀`, content[1]]
    : [`Welcome to ${NAME}! 🚀`, `Your new dashboard is now up and running at ${address}`];

  const art = banner(NAME.toUpperCase());
  const artWidth = Math.max(...art.map(displayWidth));
  /* The inner width is the widest line plus one space of padding on each side. */
  const innerWidth = Math.max(artWidth, ...measured.map(displayWidth)) + 2;
  const pad = (text, to = innerWidth - 2) => text + ' '.repeat(Math.max(to - displayWidth(text), 0));

  const wall = chars.GREEN;
  const rule = `${wall}${'━'.repeat(innerWidth)}${chars.RESET}`;
  const artBlock = art
    .map((row) => `${chars.CYAN}${pad(row)}${chars.RESET}`)
    .join(chars.BR);
  const body = content
    .map((text) => `${wall}┃${chars.RESET} ${chars.CYAN}${pad(text)}${chars.RESET} ${wall}┃${chars.RESET}`)
    .join(chars.BR);

  if (isDocker) {
    const stars = `${chars.BLUE}${'*'.repeat(innerWidth + 2)}${chars.RESET}`;
    return `${stars}${chars.BR}${artBlock}${chars.BR}${chars.BR}${body}${chars.BR}${stars}${chars.BR}${chars.BR}`;
  }
  return `${artBlock}${chars.BR}${chars.BR}`
    + `${wall}┏${rule}┓${chars.RESET}${chars.BR}`
    + `${body}${chars.BR}`
    + `${wall}┗${rule}┛${chars.RESET}${chars.BR}${chars.BR}`;
};

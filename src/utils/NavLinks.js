
/* True when the string looks like an absolute http(s) URL */
export const isHttpUrl = (str) => /^(http|https):\/\/\S+/.test(str);

/* Map a link's `target` config value to a valid HTML anchor target */
export const resolveLinkTarget = (link) => {
  const t = link && link.target;
  if (t === 'sametab') return '_self';
  if (t === 'parent') return '_parent';
  if (t === 'top') return '_top';
  return '_blank';
};

/* Intercept click to open the link in a separate popup window when configured */
export const openLink = (link, event) => {
  if (link && link.target === 'newwindow') {
    event.preventDefault();
    const { width, height } = window.screen;
    window.open(link.path, '_blank', `width=${width},height=${height},noopener,noreferrer`);
  }
};

/* The nav links for the shell. Workcenter has no sub-pages, so this is the
 * configured list. Each entry: { path, title, target? }. */
export const buildAllLinks = (extraLinks = []) => [...extraLinks];

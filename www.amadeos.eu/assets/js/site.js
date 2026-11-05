// Marks the menu entry of the current page once HTMX has loaded the header (includes/header.html).
document.body.addEventListener('htmx:afterSettle', () => {
  const page = window.location.pathname.replace(/\/$/, '/index.html');
  document.querySelectorAll('[data-nav]').forEach((link) => {
    const active = new URL(link.href, document.baseURI).pathname === page;
    link.classList.toggle('active', active);
    if (active) link.setAttribute('aria-current', 'page');
  });
});

// Look switch in the header: Horizon (the default) or Classic. The choice stays in this browser only
// (localStorage, no cookie); the inline script in each page's <head> applies it before the page is drawn.
function applyLook(look) {
  document.documentElement.dataset.look = look;
  document.querySelectorAll('.look button').forEach((button) => button.setAttribute('aria-pressed', button.dataset.look === look));
}
document.body.addEventListener('click', (event) => {
  const button = event.target.closest('.look button');
  if (!button) return;
  try { localStorage.setItem('look', button.dataset.look); } catch (e) { /* private window: not remembered */ }
  applyLook(button.dataset.look);
});
document.body.addEventListener('htmx:afterSettle', () => applyLook(document.documentElement.dataset.look || 'horizon'));

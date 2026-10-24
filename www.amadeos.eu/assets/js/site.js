// Marks the menu entry of the current page once HTMX has loaded the header (includes/header.html).
document.body.addEventListener('htmx:afterSettle', () => {
  const page = window.location.pathname.replace(/\/$/, '/index.html');
  document.querySelectorAll('[data-nav]').forEach((link) => {
    const active = new URL(link.href, document.baseURI).pathname === page;
    link.classList.toggle('active', active);
    if (active) link.setAttribute('aria-current', 'page');
  });
});

// Marks the menu entry of the current page once HTMX has loaded the header (includes/header.html).
document.body.addEventListener('htmx:afterSettle', () => {
  const page = window.location.pathname.replace(/\/$/, '/index.html');
  document.querySelectorAll('[data-nav]').forEach((link) => {
    const active = new URL(link.href, document.baseURI).pathname === page;
    link.classList.toggle('active', active);
    if (active) link.setAttribute('aria-current', 'page');
  });
});


// Click to enlarge: every picture in the page content opens full size in a dialog over the page. Pictures that
// are already links (teasers, press downloads) and small ones (the logo) keep their own behaviour.
// Esc, a click or the close button closes it; the arrow keys go through the pictures of the page.
(() => {
  const pictures = Array.from(document.querySelectorAll('main img'))
    .filter((img) => !img.closest('a') && !(img.hasAttribute('width') && Number(img.getAttribute('width')) < 200));
  if (!pictures.length || typeof HTMLDialogElement !== 'function') return;

  const dialog = document.createElement('dialog');
  dialog.className = 'lightbox';
  dialog.setAttribute('aria-label', 'Picture');
  dialog.innerHTML = '<figure><img alt=""><figcaption></figcaption></figure>'
    + '<button type="button" class="lb-close" aria-label="Close">&#x2715;</button>'
    + '<button type="button" class="lb-prev" aria-label="Previous picture">&#x2039;</button>'
    + '<button type="button" class="lb-next" aria-label="Next picture">&#x203A;</button>';
  document.body.appendChild(dialog);
  const big = dialog.querySelector('img');
  const caption = dialog.querySelector('figcaption');
  let current = 0;

  // The caption: the figure's caption, else the heading of the card, else the window title, else the alt text.
  const captionOf = (img) => {
    const box = img.closest('figure, .app, .game-card, .game, .card');
    const text = box && box.querySelector('figcaption, h3');
    const title = img.closest('.window') && img.closest('.window').querySelector('.title');
    return (text || title) ? (text || title).textContent.trim() : img.alt;
  };

  const show = (index) => {
    current = (index + pictures.length) % pictures.length;
    const img = pictures[current];
    big.src = img.currentSrc || img.src;
    big.alt = img.alt;
    caption.textContent = captionOf(img);
    caption.hidden = !caption.textContent;
  };

  pictures.forEach((img, index) => {
    img.classList.add('zoomable');
    img.tabIndex = 0;
    img.setAttribute('role', 'button');
    img.setAttribute('aria-label', 'Enlarge picture' + (img.alt ? ': ' + img.alt : ''));
    const open = () => { show(index); dialog.showModal(); };
    img.addEventListener('click', open);
    img.addEventListener('keydown', (event) => {
      if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); open(); }
    });
  });

  const single = pictures.length < 2;
  dialog.querySelector('.lb-prev').hidden = single;
  dialog.querySelector('.lb-next').hidden = single;
  dialog.addEventListener('click', (event) => {
    if (event.target.closest('.lb-prev')) show(current - 1);
    else if (event.target.closest('.lb-next')) show(current + 1);
    else dialog.close();
  });
  dialog.addEventListener('keydown', (event) => {
    if (single) return;
    if (event.key === 'ArrowLeft') { event.preventDefault(); show(current - 1); }
    if (event.key === 'ArrowRight') { event.preventDefault(); show(current + 1); }
  });
  dialog.addEventListener('close', () => { pictures[current].focus({ preventScroll: true }); });
})();

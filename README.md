# amadeos.eu

The websites of [amadeOS](https://github.com/datazuul/amadeos), one folder per host:

| Folder | Host | Content |
|---|---|---|
| [`www.amadeos.eu`](www.amadeos.eu) | https://www.amadeos.eu (amadeos.eu redirects there) | The project website |
| `apt.amadeos.eu` (planned) | https://apt.amadeos.eu | The Debian package repository of amadeOS (ROADMAP M16) |

## www.amadeos.eu

Static HTML without a build step, in the style of www.datazuul.com: one page per menu item, the shared header
and footer are loaded with [HTMX](https://htmx.org/) from `includes/` (pages carry a `<noscript>` fallback
menu). Everything is served from the site itself: no CDN, no web fonts, no cookies, no trackers.

```
www.amadeos.eu/
  index.html why.html desktop.html system.html applications.html games.html download.html handbooks.html contribute.html
  imprint.html privacy.html robots.txt sitemap.xml
  includes/header.html includes/footer.html   shared menu and footer (links are root-relative)
  assets/css/amadeos.css                      Warm Motif palette and Motif bevels of the amadeOS desktop
  assets/js/htmx.min.js                       HTMX 2.0.6
  assets/js/site.js                           marks the menu entry of the current page
  assets/images/                              screenshots from the amadeOS User's Handbook, at most 1280 px wide
```

A new page: copy a page such as `why.html`, change title, description and content, add it to
`includes/header.html` and `sitemap.xml`.

### Run locally

HTMX loads the includes over HTTP, so open the site through a local web server, not as `file://`:

```bash
python3 -m http.server 8080 -d www.amadeos.eu
```

and open <http://localhost:8080/>.

### Deploy

With Ansible from [datazuul-devops](https://github.com/datazuul/datazuul-devops), which expects this repository
next to it:

```bash
cd ../datazuul-devops/ansible
ansible-playbook -i inventories/production playbooks/deploy-www.amadeos.eu.yml
```

The playbook sets up nginx for www.amadeos.eu and amadeos.eu, gets the Let's Encrypt certificate and copies
`www.amadeos.eu/` to `/var/www/www.amadeos.eu` on the server (rsync, removing files that are gone here).

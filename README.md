# amadeos.eu

The websites of [amadeOS](https://github.com/amadeos-eu/amadeos), one folder per host:

| Folder | Host | Content |
|---|---|---|
| [`www.amadeos.eu`](www.amadeos.eu) | https://www.amadeos.eu (amadeos.eu redirects there) | The project website |
| [`apt.amadeos.eu`](apt.amadeos.eu) | https://apt.amadeos.eu | The signed apt repository of amadeOS (ROADMAP M16), built and uploaded by the workflow `apt-repository.yml` |

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
  assets/js/site.js                           marks the menu entry of the current page; click to enlarge pictures
  assets/images/                              screenshots from the amadeOS User's Handbook, at most 1280 px wide
```

A new page: copy a page such as `why.html`, change title, description and content, add it to
`includes/header.html` and `sitemap.xml`.

### Run locally

HTMX loads the includes over HTTP, so open the site through a local web server, not as `file://`. Any static
server works; run one of these from the repository root and open <http://localhost:8080/>:

```bash
# Node.js (npm): no install, npx fetches http-server once; -c-1 turns off caching so edits show on reload
npx http-server www.amadeos.eu -p 8080 -c-1

# Java 18 or newer: the JDK's own web server
jwebserver -d "$PWD/www.amadeos.eu" -p 8080

# Python 3
python3 -m http.server 8080 -d www.amadeos.eu
```

### Deploy

With Ansible from the private repository [amadeos-devops](https://github.com/amadeos-eu/amadeos-devops), which
expects this repository next to it (and datazuul-devops in `../../datazuul/`, for the shared server setup):

```bash
cd ../amadeos-devops/ansible
ansible-playbook playbooks/sync-www.amadeos.eu.yml
```

This only copies `www.amadeos.eu/` to `/var/www/www.amadeos.eu` on the server (rsync, removing files that are gone
here); nginx, the certificate and the rest of the server stay untouched. `git pull` this repository first, otherwise
the old state goes out. The full playbook `deploy-www.amadeos.eu.yml` also sets up nginx for www.amadeos.eu and
amadeos.eu and gets the Let's Encrypt certificate; it is only needed when the server setup of the site changes.

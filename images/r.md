# واحد العراق — World Cup Streaming Platform

A full-stack, production-ready sports streaming destination built with PHP + SQLite, served by Nginx on Debian Linux.

---

## Project Structure

```
ONEIQ/
├── index.html          ← Public landing page
├── goal.html           ← Admin dashboard (served at /goal)
├── api.php             ← REST API (GET public, POST/PUT/DELETE admin-only)
├── auth.php            ← Login endpoint (returns bearer token)
├── config.php          ⚠️  EDIT BEFORE DEPLOY — passwords here
├── db.php              ← Shared PDO helper
├── init_db.php         ← Run once to create DB + seed data
├── nginx.conf          ← Production Nginx server block
├── deploy.sh           ← One-shot Debian deployment script
└── assets/
    ├── css/
    │   ├── style.css   ← Main site styles
    │   └── admin.css   ← Admin dashboard styles
    └── js/
        ├── main.js     ← Index page logic
        └── admin.js    ← Admin dashboard logic
```

---

## Deployment (Debian + Nginx)

### Step 1 — Edit config.php first!

```php
define('ADMIN_TOKEN',    'your-very-long-random-token-here');
define('ADMIN_PASSWORD', 'your-strong-password-here');
```

### Step 2 — Upload files to server

```bash
scp -r ./ONEIQ root@your-server:/tmp/oneiq
```

### Step 3 — Run the deploy script

```bash
ssh root@your-server
cd /tmp/oneiq
sudo bash deploy.sh
```

This will:
- Install `nginx`, `php8.2-fpm`, `php8.2-sqlite3`
- Copy files to `/var/www/oneiq`
- Initialise the SQLite database
- Set correct permissions
- Install and enable the Nginx config
- Reload Nginx

### Step 4 — Add your domain

Edit `/etc/nginx/sites-available/oneiq` and replace `yourdomain.com` with your actual domain.

### Step 5 — HTTPS (optional but recommended)

```bash
apt install certbot python3-certbot-nginx
certbot --nginx -d yourdomain.com
```

---

## URLs

| URL | Purpose |
|-----|---------|
| `http://yourdomain.com/` | Public streaming landing page |
| `http://yourdomain.com/goal` | Admin dashboard |
| `http://yourdomain.com/api.php` | JSON REST API |

---

## Nginx PHP-FPM Version

If you are using a different PHP version, update the socket path in `nginx.conf`:

```nginx
# Change 8.2 to your installed version
fastcgi_pass unix:/run/php/php8.2-fpm.sock;
```

Check your installed version: `php -v`

---

## Security Notes

- The SQLite file at `/database/oneiq.sqlite` is blocked by Nginx (`deny all`)
- `config.php`, `db.php`, `init_db.php` are all blocked from web access
- Admin login uses `hash_equals()` for constant-time comparison
- Rate limiting protects the API (`30r/m`) and auth (`5 burst`) from brute force
- Session tokens are stored in `sessionStorage` (cleared on tab close)

---

## Color Palette

| Color | Hex | Usage |
|-------|-----|-------|
| Background | `#000000` | Page background |
| Red | `#FF0000` | Accents, shapes, icons, CTA buttons |
| Lime Yellow | `#E8FF00` | Brand name, primary bold text |
| Bright Green | `#00FF00` | Tagline "قناة الاخبار الاولى" |

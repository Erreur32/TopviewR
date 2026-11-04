# btop-web

[btop](https://github.com/aristocratos/btop) dans le navigateur, servi par [ttyd](https://github.com/tsl0922/ttyd), pensé pour un usage LAN sécurisé.

## Pourquoi

L'image `bigbeartechworld/big-bear-btop` a disparu de Docker Hub (404 sur le dépôt, 401 sur le registre) et reposait sur GoTTY, abandonné depuis 2024. Conséquences : plus de mises à jour et des erreurs `[Registry] ... 401` dans Dockhand.
Cette image la remplace : btop 1.4.8 compilé depuis les sources (avec support GPU), ttyd 1.7.7, base Alpine 3.24, 31 Mo, reconstruite chaque semaine.

## Démarrage rapide

```sh
cp .env.example .env
# éditer .env : BTOP_PASS (12 caractères min.), BTOP_TLS_SAN (IP et nom du serveur)
docker compose up -d
```

Ouvrir `https://<ip-du-serveur>:7681`. Le navigateur prévient une fois que le certificat est auto-signé : accepter l'exception, puis se connecter.

## Sécurité

**Ce qui est protégé**

| Risque | Protection | Vérifié par |
|---|---|---|
| Tuer des processus de l'hôte avec la touche `k` | btop tourne en UID 10001 (`su-exec`), jamais en root | `tests/test.sh` : `kill` sur le PID 1 de l'hôte refusé |
| Mot de passe lu sur le réseau | TLS intégré (`BTOP_TLS=auto`) | test HTTPS |
| Démarrage sans protection | refus sans mot de passe ; 12 caractères minimum | test |
| Page piégée qui ouvre le WebSocket | `ttyd -O` (origine vérifiée) | test |
| Trop de sessions btop | 3 clients max (`BTOP_MAX_CLIENTS`) | |
| Conteneur trop puissant | compose sans `privileged`, `cap_drop: ALL` + 3 capacités, `read_only`, `no-new-privileges` | |
| Failles connues dans l'image | scan Trivy à chaque build (0 faille au 2026-11-04) | `make scan` |

**Limites connues**

- **Le mot de passe est visible dans `ps` sur l'hôte**, et dans la liste des processus de btop (ligne de commande de ttyd). ttyd n'accepte l'identifiant qu'en argument. Toute personne ayant un shell sur le serveur peut le lire : utiliser un mot de passe dédié, jamais réutilisé ailleurs.
- **Pas de protection contre la force brute.** ttyd ne limite pas les essais. Ne jamais exposer le port sur Internet. Pour un accès distant : VPN (WireGuard, Tailscale) ou reverse proxy avec SSO, puis `BTOP_AUTH_HEADER` (le port ne doit alors être joignable que par le proxy).
- ttyd lui-même tourne en root (il lit les certificats et lance btop) ; seul btop, la partie pilotée au clavier, est non root.
- Le dossier de config monté est passé en propriété de l'UID 10001.

## Ce que btop voit (mesuré le 2026-11-04)

| Affichage | `docker-compose.yaml` (sécurisé) | `docker-compose.legacy.yaml` (ancien compose) |
|---|---|---|
| CPU, mémoire, uptime | ✅ | ✅ |
| Processus de l'hôte | ✅ (`pid: host`) | ✅ (`/proc` monté) |
| Réseau réel de l'hôte | ✅ (`network_mode: host`) | ❌ ne voit que l'interface du conteneur (172.17.x) |
| Disques de l'hôte | ✅ via `/:/host:ro,rslave` | non vérifié |
| GPU | non testé (machine de test sans GPU) | non testé |

GPU : décommenter `devices: /dev/dri` pour Intel ou AMD. Les GPU AMD intégrés passent par `/sys` (nouveauté btop 1.4.8). NVIDIA risque de ne pas marcher : la bibliothèque `libnvidia-ml` est compilée pour glibc, l'image est en musl.

## Variables

| Variable | Défaut | Rôle |
|---|---|---|
| `BTOP_USER` / `GOTTY_AUTH_USER` | `admin` | identifiant |
| `BTOP_PASS` / `GOTTY_AUTH_PASS` | obligatoire | mot de passe (`BTOP_*` prioritaire) |
| `BTOP_NO_AUTH=true` ou `GOTTY_AUTH_ENABLED=false` | | désactive l'auth (déconseillé) |
| `BTOP_ALLOW_WEAK_PASS` | `false` | accepte moins de 12 caractères (toléré avec avertissement pour `GOTTY_AUTH_PASS`) |
| `BTOP_TLS` | `off` dans l'image, `auto` dans le compose | `off`, `auto` (auto-signé généré dans `/certs`), `on` (fournir `/certs/cert.pem` et `key.pem`) |
| `BTOP_TLS_SAN` | | IP et noms ajoutés au certificat, séparés par des virgules |
| `BTOP_PORT` | `7681` | port |
| `BTOP_BIND` | toutes | IP ou interface d'écoute |
| `BTOP_UID` / `BTOP_GID` | `10001` | utilisateur de btop (choisi pour ne correspondre à aucun compte de l'hôte) |
| `BTOP_MAX_CLIENTS` | `3` | sessions simultanées |
| `BTOP_TITLE` | `btop @ <hostname>` | titre de l'onglet |
| `BTOP_FONT_SIZE` | `14` | taille de police |
| `BTOP_THEME` | `dark` | `light` pour un fond clair |
| `BTOP_AUTH_HEADER` | | auth faite par un reverse proxy (`ttyd -H`) |
| `BTOP_ARGS`, `TTYD_EXTRA_ARGS` | | options supplémentaires de btop et ttyd |

Config btop : `./config/btop.conf`, créé au premier lancement s'il manque (jamais écrasé). Par défaut `use_fstab = false` et les faux disques de Docker sont filtrés, pour afficher les vrais disques de l'hôte.

## Build

```sh
make build    # image locale btop-web:dev
make test     # build + tests de bout en bout (Docker et python3 requis)
make scan     # Trivy
make buildx   # amd64 + arm64 sans push (demande QEMU/binfmt pour arm64)
REGISTRY=ghcr.io/erreur32 make push
```

Monter de version btop à la main : changer `BTOP_VERSION` et `BTOP_SHA256` dans le `Dockerfile` (`curl -fsSL https://github.com/aristocratos/btop/archive/refs/tags/vX.Y.Z.tar.gz | sha256sum`).

## Mises à jour automatiques (GitHub)

- `build.yml` : à chaque push, chaque PR et chaque lundi. Build, tests, Trivy, puis push multi-arch sur `ghcr.io/erreur32/btop-web` avec les tags `latest`, `1.4.8` et `1.4.8-AAAAMMJJ`.
- `btop-release.yml` : chaque lundi, ouvre une PR si une nouvelle version de btop est sortie. Les PR créées par `GITHUB_TOKEN` ne déclenchent pas la CI : la fermer et la rouvrir, ou lancer `build` à la main.
- Dependabot : versions des actions et de l'image Alpine.
- Après le premier push, passer le paquet GHCR en public (ou faire un `docker login ghcr.io` sur les serveurs).

## Migration depuis big-bear-btop

Avant tout, garder une copie de l'ancienne image si elle est encore en cache :
```sh
docker image ls | grep big-bear && docker save bigbeartechworld/big-bear-btop -o big-bear-btop.tar
```

**Étape 1 : remplacement direct** (rien d'autre ne change). Dans le compose actuel, remplacer seulement :
```yaml
image: ghcr.io/erreur32/btop-web:latest
```
puis `docker compose up -d`. Les `GOTTY_*` fonctionnent. Un mot de passe de moins de 12 caractères affiche un avertissement dans les logs.

**Étape 2 : passage au compose sécurisé.** Copier `docker-compose.yaml` et `.env.example` à côté de l'ancien, remplir `.env` (`BTOP_CONTAINER_NAME=BTOP_media`, nouveau mot de passe, `BTOP_TLS_SAN`), déplacer l'ancien `.config/` vers `config/`, puis `docker compose up -d`. L'adresse devient `https://`.

**Étape 3 : Dockhand.** Réactiver la mise à jour auto pour BTOP_media et BTOP_plus.

**Retour arrière** : remettre un tag daté précédent (`image: ghcr.io/erreur32/btop-web:1.4.8-20261104`), ou l'ancienne image depuis la copie : `docker load -i big-bear-btop.tar`.

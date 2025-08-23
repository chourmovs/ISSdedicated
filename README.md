<div align="center">

# ⚔️ Insurgency: Sandstorm Dedicated Server (Docker)

![Insurgency Banner](https://cdn.cloudflare.steamstatic.com/steam/apps/581320/header.jpg)

Un **serveur dédié Insurgency: Sandstorm** clé en main dans un conteneur Docker :  
→ XP classé activable,  
→ Mutators & Mods (mod.io),  
→ Bots **“enragés”** via [AiModifier](https://mod.io/g/insurgencysandstorm/m/aimodifier),  
→ Console admin côté client,  
→ Support complet Portainer & docker-compose.

[![Docker Pulls](https://img.shields.io/docker/pulls/chourmovs/issdedicated)](https://hub.docker.com/r/chourmovs/issdedicated)
[![GitHub stars](https://img.shields.io/github/stars/chourmovs/issdedicated?style=social)](https://github.com/chourmovs/issdedicated)

</div>

---

## ✨ Fonctionnalités principales

- 🐳 **Déploiement Docker/Portainer** prêt à l’emploi  
- 🔓 **XP activable** avec `GSLT_TOKEN` + `GAMESTATS_TOKEN`  
- 🛡️ **Menu Admin côté client** (`Admins.txt`)  
- 🧩 **Mods & Mutators auto-download** depuis mod.io  
- 🤖 **Bots paramétrables** (nombre, quota, difficulté, squad size…)  
- 💀 **AiModifier “Enraged”** : bots plus précis, temps de réaction réduits, comportements agressifs  
- 🔀 **MapCycle configurable** (PvP, Coop, Outpost/Horde)  

---

## 🚀 Déploiement rapide

### 1. Récupérer le dépôt
```bash
git clone https://github.com/chourmovs/issdedicated.git
cd issdedicated
```

### 2. Lancer via docker-compose
```bash
docker-compose up -d
```
⚠️ Pense à définir tes tokens XP dans Portainer ou .env.

⚙️ Exemple docker-compose
```bash
version: "3.9"

services:
  sandstorm:
    image: chourmovs/issdedicated:main
    container_name: sandstorm
    restart: unless-stopped
    ports:
      - "27102:27102/udp"
      - "27131:27131/udp"
      - "15000:15000/udp"
      - "27015:27015/tcp"
    volumes:
      - /opt/sandstorm:/opt/sandstorm
      - /opt/steam:/home/steam/Steam
    environment:
      SS_HOSTNAME: "CHOURMOVS ISS (Push) • Bots Enragés"
      SS_GAME_MODE: "Outpost"
      SS_SCENARIO: "Scenario_Hideout_Outpost_Security"
      SS_MAXPLAYERS: "1"
      SS_BOTS_ENABLED: "1"
      SS_BOT_NUM: "0"
      SS_BOT_QUOTA: "10.0"
      SS_BOT_DIFFICULTY: "0.8"

      # XP classé (⚠️ RCON_PASSWORD doit rester vide)
      GSLT_TOKEN: "${GSLT_TOKEN}"
      GAMESTATS_TOKEN: "${GAMESTATS_TOKEN}"
      RCON_PASSWORD: ""

      # Admins (SteamID64 séparés par virgule)
      SS_ADMINS: "76561198000000001,76561198000000002"

      # Mods & Mutators
      SS_MODS: "1141916"       # AiModifier (mod.io)
      SS_MUTATORS: "AiModifier"

      # Bots Enragés (AiModifier placeholders)
      AIMOD_DIFFICULTY: "0.9"
      AIMOD_ACCURACY: "1.0"
      AIMOD_REACTION: "0.1"
      AIMOD_ALLOW_MELEE: "0"
      AIMOD_STAY_IN_SQUADS: "1"
      AIMOD_SQUAD_SIZE: "6"
```
---
## 🧩 Mutator AiModifier (Enraged Mode)

Le mutator AiModifier rend les bots :

plus rapides à réagir,

plus précis,

plus intelligents (squads, cover, flank, rush).

👉 Grâce aux placeholders AIMOD_*, tout se configure directement via docker-compose / Portainer.

Exemple :

AIMOD_DIFFICULTY: "0.9"
AIMOD_ACCURACY: "1.0"
AIMOD_REACTION: "0.1"

##📜 Console Admin

Admins.txt auto-généré depuis SS_ADMINS.

Côté client, ouvre la console admin (~) ou le menu admin (Numpad -).

---
## 🎮 Modes supportés

PvP : Push, Firefight, Skirmish, Domination

Coop : Checkpoint, Outpost, Survival

Exemple MapCycle (Horde Solo) :

SS_MAPCYCLE: |
  Scenario_Hideout_Outpost_Security
  Scenario_Farmhouse_Outpost_Security
  Scenario_Crossing_Outpost_Security

---

	
</div>
🤝 Contributions

Issues & PR bienvenues !

Mutators additionnels (ex: HeadshotOnly, Hardcore) facilement intégrables.

📜 Licence

Ce projet est distribué sous licence MIT.
Insurgency: Sandstorm © New World Interactive.

<div align="center">

# ⚔️ Bon jeu, et prépare-toi à survivre à la HORDE ENRAGÉE 💀

</div>

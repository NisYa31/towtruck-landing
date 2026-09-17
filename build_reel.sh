#!/usr/bin/env bash
#
# build_reel.sh — Montage vertical prêt pour Instagram Reels — ROLLS-ROYCE CULLINAN.
#
# Adapté du montage Lamborghini Urus (commit 341dbbd). Le MOTEUR est repris
# à l'identique : seule la CONFIGURATION ci-dessous et les textes embarqués
# changent. Ne pas réécrire le moteur, il est éprouvé.
#
# Assemble une liste de clips (coupes franches, sans transition) en une seule
# vidéo verticale H.264, incruste des textes, et applique un fondu de sortie
# sur la toute fin.
#
# Les textes sont embarqués dans ce fichier en base64 et incrustés avec le
# filtre « overlay », présent dans toutes les compilations de ffmpeg. Aucun
# besoin de « drawtext » (qui exige libfreetype et libharfbuzz).
#
# Usage :
#   ./build_reel.sh                    # utilise VIDEO_DIR ci-dessous
#   ./build_reel.sh /chemin/vers/clips # dossier passé en argument
#   ./build_reel.sh --bandes           # liste les textes embarqués
#   OUTPUT_NAME=cullinan_v2.mp4 ./build_reel.sh
#
set -euo pipefail

# Force le point comme séparateur décimal. Sous une locale française,
# awk formaterait "19,500" au lieu de "19.500", que ffmpeg rejette.
export LC_ALL=C

# ══════════════════════════════════════════════════════════════════════
#  CONFIGURATION — tout ce qui se modifie au quotidien est ici
# ══════════════════════════════════════════════════════════════════════

# Dossier contenant les clips sources (et où sera écrit le rendu).
VIDEO_DIR="${1:-${VIDEO_DIR:-videos-cullinan}}"

# Nom du fichier de sortie.
OUTPUT_NAME="${OUTPUT_NAME:-cullinan_v1.mp4}"

# ┌────────────────────────────────────────────────────────────────────┐
# │ GRILLE PROVISOIRE — À REMPLACER AVANT LE PREMIER RENDU RÉEL        │
# │                                                                    │
# │ Les horodatages et les durées ci-dessous sont ceux de l'URUS. Ils  │
# │ sont là pour que le script soit lisible et testable, PAS pour être │
# │ lancés tels quels : aucun fichier Cullinan ne correspondra, et le  │
# │ script s'arrêtera sur « aucun fichier ne correspond à             │
# │ l'horodatage … ». C'est voulu.                                     │
# │                                                                    │
# │ Pour produire la vraie grille :                                    │
# │   1. relever la longueur réelle des clips (ffprobe -count_frames)  │
# │   2. mesurer le tempo du morceau     : ./tempo.py <musique>        │
# │   3. calculer la grille               : ./grille.py <bpm> <images> │
# │   4. recopier ici les lignes produites par grille.py               │
# └────────────────────────────────────────────────────────────────────┘
#
# Montage : un clip par ligne.
#   <horodatage>  <début>  <fin>   # commentaire libre
# - horodatage : les 6 chiffres du nom de fichier (hf_AAAAMMJJ_XXXXXX_....mp4)
# - début/fin  : secondes depuis le DÉBUT du fichier source (point décimal, pas
#                de virgule : 2.5 et non 2,5)
#
# Pour réordonner le montage, il suffit de déplacer les lignes.
CLIPS=(
  "192809   0   2.5417   # ouverture, hero           — 61 images,  4 temps"
  "194405   0   5.0417   # plan long, mouvement      — 121 images, 8 temps"
  "193836   0   1.8750   # respiration               — 45 images,  3 temps"
  "194945   0   1.8750   # poste de conduite         — 45 images,  3 temps"
  "201411   0   1.9167   # détail intérieur          — 46 images,  3 temps"
  "201929   0   1.8750   # détail intérieur          — 45 images,  3 temps"
  "200403   0   5.0417   # 3/4 arrière, plan final   — 121 images, 8 temps"
)

# Textes incrustés : "<début> <fin> <texte> <x> <y>"
#
#   début/fin : secondes dans le MONTAGE FINAL (pas dans le clip source)
#   texte     : un des textes embarqués — liste : ./build_reel.sh --bandes
#   x, y      : position du CENTRE du texte, en fraction de l'image
#
# Zone sûre Instagram : garder y entre 0.12 et 0.78, sinon l'interface
# (pseudo, légende, boutons) recouvre le texte.
#
# Parti pris de design, repris tel quel de l'Urus : chaque texte est un
# bandeau pleine largeur ancré en haut du cadre, composé d'un dégradé sombre,
# d'un filet, d'un libellé discret et d'une valeur forte. Le dégradé intègre
# le texte à l'image au lieu de le poser dessus.
#
# x=0.50 et y=0.00 collent le bandeau en haut, pleine largeur. Descendre le
# bandeau (y plus grand) casse le dégradé : il n'a de sens que bord à bord.
#
# Spécifications relevées sur octane.rent (Rolls-Royce Cullinan Black, Dubai) :
#   593 ch → « 593 HP »   |   0-100 en 5.0 sec   |   250 km/h
# La convention « HP » pour une valeur en ch reprend celle du bandeau Urus
# (650 ch sur la fiche → « 650 HP » à l'écran), pour que la série reste
# cohérente d'un véhicule à l'autre.
#
# Les fenêtres ci-dessous suivent la grille PROVISOIRE et sont à recaler en
# même temps qu'elle.
OVERLAYS=(
  "0.30   2.45   model      0.50  0.00   # ROLLS-ROYCE / CULLINAN"
  "3.15   7.35   power      0.50  0.00   # POWER / 593 HP"
  "9.55   11.25  accel      0.50  0.00   # ACCELERATION / 0-100 KM/H IN 5.0S"
  "15.77  19.60  topspeed   0.50  0.00   # TOP SPEED / 250 KM/H"
)

# Durée du fondu d'apparition et de disparition des textes.
TEXT_FADE=0.5

# Format de sortie. Les clips sources étant en 24 fps, garder FPS=24 évite
# de dupliquer une image sur quatre. Mettre 30 si les sources changent.
WIDTH=1076
HEIGHT=1928
FPS=24

# Fondu de sortie, en secondes, appliqué à la fin du montage global.
# Mettre 0 pour aucun fondu. (Aucune transition entre les clips : coupe franche.)
FADE_OUT=1

# Encodage H.264. CRF plus bas = meilleure qualité / fichier plus lourd.
CRF=18
PRESET=slow

# ── Musique ───────────────────────────────────────────────────────────
# Chemin vers un fichier audio (mp3, wav, m4a...). Laisser vide pour une
# vidéo sans musique. Chemin relatif = relatif au dossier des clips.
# À REMPLIR : registre Cullinan (cinématographique lent / orchestral minimal,
# 80-100 BPM), pas le registre Urus.
MUSIC="${MUSIC:-}"

# Seconde du morceau à laquelle commencer. Sert à attraper le bon passage :
# un refrain ou une montée tombent rarement à 0:00. Voir ./find_drop.sh
MUSIC_START=0

# Fondu d'entrée de la musique, en secondes. Le fondu de sortie est calé
# automatiquement sur FADE_OUT, pour que son et image s'éteignent ensemble.
MUSIC_FADE_IN=0.8

# Volume cible en LUFS. -14 est la valeur vers laquelle Instagram, TikTok et
# YouTube ramènent tout. Viser cette cible évite qu'ils écrasent le morceau.
MUSIC_LUFS=-14

# Piste audio quand MUSIC est vide : 1 = piste AAC muette (les plateformes la
# préfèrent à une absence totale de piste), 0 = aucune piste audio.
SILENT_AUDIO=1

# ══════════════════════════════════════════════════════════════════════
#  MOTEUR — normalement rien à toucher en dessous
# ══════════════════════════════════════════════════════════════════════

die() { printf '\033[31merreur :\033[0m %s\n' "$*" >&2; exit 1; }
info() { printf '\033[36m•\033[0m %s\n' "$*"; }

# base64 se décode avec -d sur Linux et macOS récent, -D sur macOS ancien.
if printf 'QQ==' | base64 -d >/dev/null 2>&1; then
    B64D=(base64 -d)
else
    B64D=(base64 -D)
fi

# Écrit les textes embarqués dans le dossier passé en argument.
# Écrit les textes embarqués dans le dossier passé en argument.
extract_bands() {
    local d=$1
    "${B64D[@]}" > "$d/model.png" <<'B64_MODEL'
iVBORw0KGgoAAAANSUhEUgAABDQAAAIwCAQAAADTpvPdAAAnd0lEQVR42u3dd5gV1dkA8LO7lEWW
jiBKEbAgqKgIVuwiihRbrJBYosbeYuyJxoK9JPbPaExi7wiCoqJiQYOgIIiFDlIEQcpStnx/EBTl
3u2H3Vl+v3keH5wzc+65797dffc9Z2Yywn8CAEAUNUKhIAAAcWQKAQAQi4oGABCNigYAEI2KBgAg
0QAAksfUCQAQjYoGABCNigYAEI2KBgAQjYoGABCNigYAINEAAJLH1AkAEI2KBgAQjYoGABCNigYA
EI2KBgAQjYoGACDRAACSx9QJABCNigYAEI2KBgAQjYoGABCNigYAEI2KBgAg0QAAksfUCQAQjYoG
ABCNigYAEI2KBgAQjYoGABCNigYAEI2KBgAQjYoGACDRAACSx9QJABCNigYAEI2KBgAQjYoGABCN
igYAEI2KBgAQjYoGABCNigYAEI2KBgAQjYoGACDRAACSx9QJABCNigYAEI2KBgAQjYoGABCNigYA
EI2KBgAQjYoGABCNigYAEI2KBgAQjYoGABCNigYAEI2KBgAQjYoGABCNigYAINEAAJLH1AkAEI2K
BgAQjYoGABCNigYAEI2KBgAQjYoGABCNigYAEI2KBgAQjYoGABCNigYAEI2KBgAQjYoGABCNigYA
EI2KBgAQjYoGABCNigYAEI2KBgAQjYoGABCNigYAEI2KBgAQjYoGABCNigYAEI2KBgAQjYoGABCN
igYAEI2KBgAQjYoGABCNigYAEI2KBgAQjYoGABCNigYAEI2KBgAQjYoGABCNigYAEI2KBgAQjYoG
ABCNigYAEI2KBgAQjYoGABCNigYAEI2KBgAQjYoGABCNigYAEI2KBgAQjYoGABCNigYAEI2KBgAg
0QAAksfUCQAQjYoGABCNigYAEI2KBgAQjYoGABCNigYAEI2KBgAQjYoGABCNigYAEI2KBgAQjYoG
ABCNigYAEI2KBgAQjYoGACDRAACSx9QJABCNigYAEI2KBgAQjYoGABCNigYAEI2KBgAQjYoGABCN
igYAEI2KBgAQjYoGACDRAACSx9QJABCNigYAEI2KBgAQjYoGABCNigYAEI2KBgAQjYoGABCNigYA
INEAAJLH1AkAEI2KBgAQjYoGABCNigYAEE2Vr2gU3lyZr57xJx8RACg7FQ0AQKIBACRPRjhWEACA
OFQ0AIBoXN4KAESjogEARKOiAQBEo6IBAEg0AIDkMXUCAESjogEARKOiAQBEo6IBAEg0AIDkMXUC
AESjogEARKOiAQBEo6IBAESjogEARKOiAQBINACA5DF1AgBEo6IBAESjogEARKOiAQBINACA5DF1
AgBEo6IBAESjogEARKOiAQBINACA5DF1AgBETDQSYOBOf+r4632rC35YNenHt+Y+8u2M5aV4uxl9
Wx7cYo+mzbMb11pVMG/F+MWvf/fktAUrSz6Kg98aPqcsoy/9eSGEsGPDE7bco+k29RvUrJm5LG/W
8vGLh8x+aurKguoU2+bZEw9vVOvH1du9Ojt3/dbNsice3rDWwlUdX527oriesjL6tTykxR5Nm9dp
VGtF/pzccYte++6paUtWly0K62r78tRlflgAbFQVjZqZzbKbZXdvdmnHi0ff/3XJzjmq9c07t8/5
uYe2OW1zem9xy853TLx+/Ir8Er5wYRkjVurz6mQ9uNtJbTN++v8GNRs06NjgN62v2+GY9z5eUH1i
Ozf3otGP7lG/5j1djn5v/da7ujSsFcJFo+fmFjeC3lvc3mXremv/L6fGVvW2qndEq4E7XTH2wa/L
HZJClT+AalzRWOPC0f9d59drnRpb1u3dsvcWdbLu67Y8/5+TS/BX685r/mr9esmrs8YtWrAyp8aW
OT1a7NusTtaV2x+02eEjvl9Ztd7vC/v03DyEiYsf/mbUgrm5mRmb1dml8Sntd2zYuu7QA7q8NmVp
9YntY5NP2PLgFke17rXF4Fm/bDmkxbFtQhj2XfFjuHL7v3bOCCFMXvryzM9/WLhq09rt6x3Xpm1O
41oPdOvc6KyPSxKFy8eO/SFNMrTCjwqAap9ojF80cv4v9zz8zRGtnuuemXH7LsVPJ1y83Z86hrAs
79z//nNywU9/nd44vluTx/bYrsFuTV/ad7838qrQX62Hbt5z8xBemXnMe6v+986+XvLevHsnPbz7
79o1qjVwp2NHVqfYnvHxuF51a9zbdcTcZXnr1nTu6xbC0rwzRhU3/t+1u75zCKsKLhr9wNf5P73S
VZ/1b/tAt+ysP2z9xaJ7vyo+Cv9dUJbpLQCKkhkKE7Gtsd7+F6c/PS2EJrX3bVb0+Z0aDNw5hBX5
Bw5/9JuCgnVbPv5+72HjF4Ww16YXdijrKGKc17NFCCFcOXZV/rp78wrOGjV/RWHo3Cg7szrFdsqS
qz8LoU3da3dcd+81O7TLCeGKMdOWFn325tn3dQuhoLDviHsn5a8zgoKCf3576FsFhSHcuFOjmpG+
tjabzWYrckv85a3vzgshhHb1iimKd6qREcJVY0d9v37bwlXHj8wvDOHSTnWyqs772jQ7dck+N7/r
a/We6vBKideUJCS2d3856vsQzu/QudHaPZ0aXrxdCB/ML74WcVHHOlkh3DFx6Oz120bMfejr4d/9
8dN8aywAKmnqJDk/gFMuyCssDCGEjCIX69XJOqZNCAtW3jcp9VHjf3hx+tFtmtbutcVz08o2irKO
Pr05uSGE0GOz/0z5dcu0pdUxtgWFp334aa+amQ/ttsfQgsIQMsKD3Wpmrsw/9cOCYq+xOaltCCvz
b/0i9Qj+MCrW1wiAkkydJNweTUMI4eslRR2z56a1MkMYMis3bRXg6WkhhHBwi6rzvl6eEUIID+7+
u/aZGRtHbMcvuml8CN2anrVNCCH8fuu9moXw13FfLi7uvA4NmmeH8O68eRZsAkg0Klq3pie0DWHe
ivfmFXXUDo1CCCFVaX+tj+aHEEKnBlXnnb0z91+TQ6hb49E9px15/27HtNm8TvWP7Q3jJiwO4Yad
N6/TLHvgLiF89sMtXxR/1g4NixsBAJUnGVMnhf/77zpjrZ3VNufoNpdtXzMzhMs+XZlX1OlNaoUQ
wpzc9O91zvIQQmhep8hopBhFWUdfEqe8P3XpHztlZ7Xc5MxtztwmhClL3583dPbQWQtWVsPYhhBC
WJV/6gfv96xf856uKwsa1covPPWD1SVYibJmBN8tL9cnuTCEEN44KHVj96Ej5/lRAVDWRCMx3jg4
1d78wivHPPpN0WfWqxlCCMuK+IWZV7gyv3ZWVVoMGkJe4TVj75908lb9WnVpkpkRQtuctjkntVuZ
/58p1342fVn1jO1H8//+5XnbHdUmhBDumDC6RLcly6kZQgjL83wzA6hoVLDvcgfN+PuX434o7rg1
v4TqF/Fea2XWzgphWV4JorHB7gy65u/0Gz+/8fOGtfbYdO/mezXbrWl2Vu2sU7bq2+qIt9+bWw1j
G0K44tO+rdrkhPDNkj+PKdkZy1eHEEL9muX/JF/y39SpzbgfLBIF2AgqGud9/MlP8/BNa7+wf83M
2cvP+qgkly3OXh5CCK3rpj9i801CCGFmFX2exaJVr816bVYIdbIObXnlDrs0aVL7iX22e3Fp2r/h
n9tvTU1gjaenHvdOcmK7LO/OCXd1C+G28bklvID3u9wQQtgyp/xx/mzhCDfsAqhgCVoMOnHRR/PX
bq/OvGNCCF2aXNixJGd+/kMIIeyxafojujX9+biqKzf/hWm7DX59dggtNxnQvrrGds19SEv+4Ljx
i0IIYe9mvpkBqmZFIzmLQcO6Y71u7PFtW9e9bucXp327pLjTP5q3ZHW9moe2bFxrYZqFlL/ZMoQQ
hs0qwWLQUMbFoKFiIp1XeNPnPTYPYcdG6fu784vnpv78f9OWlvZdVUJs1x9Riaeavl48Y1mrul2b
dmwwYVGq9qbZQw4aOO6FaRvuawRAIisav7Q87/xRIdTJemjP4o9dVfDE5BDqZP1ph9TtHRv2bRXC
9GVvzK4q726nxlfs+Pz+nRqmaiv+qpP35z015eftw/nVPbaPfxtCCDfskrr1li5dmz6/f9/WvtkB
JBql8tL0V2eEcECLU7Yu/tiB43LzQ7ik02Et129rUOuJfWpkhvDnMVXnNtXdmt6wy5FtLk35y7t7
8xBC+OpHsV3r7gmLVoXQr/VFndZvO3Xrk7cO4bOFg2b4ZgeonEQjwY9UO/ej3PwQbuu6WXZxPUxd
8sdPQsjMeOmAczvUyFi3pXOjdw/t3DiEl6f/8+uq80i1JybPyQ1hQPurO2f+6sxuTa/fJYSV+c9O
qVaxXX9EpYjY/NyzPwwhhNu73tG1Xo2f99fMuKbzw3uFsCzvxHd++bg3j1Sz2Wy2DbXVSHKWNHXp
DZ9dv0ujWn/f/ei3izv23ombZv95p5qZ9+x+QaeXpo9d8P3KujW2zOmxxUGbZ4QQhs068Z2S/cm9
a9Ma690SfO6KMQsq9rylq/u/O+TgmpnX7dy//VOTRy+Yk5tXUL/Wtg16btG7VWZGCBd/MmNZ9Ytt
2T0xuXmd27tlhAs7Ddjqlemj5s9fkZ3VufFx7VrXDWHp6r5vfrGorF/bNeavKNk9PQD4tcTeGXSN
Wz/v337bBkdt2a/1S8U+Du0vn47+/p7dt8xpV++XJfYfV98w9vbx+YUlG8VNXdZveHl6v+EVfd7w
WfsOebT7tg22rn/1Tr9smZN70agnJ1ez2JZoREW5c/y4hfftuXX9JrVP3vrkdSZ8Rs49beSkxWX/
2q4xbFbPYX5YAJQt0Ui0VQVnfzi8Zwj37vH2d4tXFXf0oOmvzezdqk/rLk3b5NStsTJ/Tu7nC4fO
empy8WdWhg/ndXzhsJa9W+/SZMuc+rUyw9K8mcs+Xzhk5kvTluWJbYrUbHaH5w9v1a9N16atc+rW
WJ43demH856cPOI73+QAlSkjHCgIAEAcNdw5AACIJVMIAACJBgCQOKZOAIBoVDQAgGhUNACAaFQ0
AACJBgCQPKZOAIBoVDQAAIkGAJA8pk4AgGhUNAAAiQYAkDymTgCAaFQ0AIBoVDQAgGhUNAAAiQYA
kDymTgCAaFQ0AACJBgCQPKZOAIBoVDQAAIkGAJA8pk4AgGhUNAAAiQYAkDymTgCAaFQ0AACJBgCQ
PKZOAIBoVDQAgGhqVMO3lNWpXZcO27Zu1bxV8xZN62bXqV2ndlbWylUrVy9a8v2iuQu/mfn1jM+/
+XTS8hW+/AAQV0boVn3ezHZb9tnn8L133S67VvHH5uWPmTTkg1fe/XRS2V7rst/edFbqllFf7H5K
2fo855i/XZK65YvJ2x9f3NlfPrNtm9Qtf7j5gRdixj2pr5z+7BBCuPe5c24t/YgGnv2nAan2dz99
5GcV8Y7H/GunbYpq7zKgrJ/o6hAdoCqqJlMn9euec8yEpyc8PfDsvTuXJM0IoUZW145/Pm304+Of
vOiEepv4IPBrZx7ZqV1VG9P27YtOM0Lof9jGGx1AohFJg5ybz5k1+G+XbLdlWc7u1O7286e/8ufT
Nsn2YWBdWZl3XFDVxvTbXsUdcXyPGlkba3SAqinhV51kZPzhqGtPb9qwfL00rPeX35/a57zbXnqn
FCcVFtESI6aF5Tq3sr7KiX7lHrsdvterI6vEV3DNXwWZJ/Qo7pjmjXvsNuT9DRHgqhYdoKpKdEWj
RdPX/3bvpeVNM9Zo1fzFWx++sk5tHwl+dvsFNavQcumDum6+afFHDThs44wOINGocPvs/PkTB1Xo
UtbT+r59f/PGPhSstU3rc35TdUYzoFdJjuq7b/26G2N0gKoqsVMnvbs/M7Bkyz5LY7ftRz687xmz
55ezm8II5xVWyojKL+GvfM2p/xr8/aIKeNVyT+XkbHLEfiU5LrvWMQc+8vKGCXHViQ5QdSW0onHU
AS/cWvFpRgghbNXqrfsb1/fBYI2G9a47o2qM5OgDSrpguf9hG190AIlGhdpt+39dF29t/bZtnhm4
YVbukwSnV5ELOUs2cRJCCPvs3KbFxhYdoOpK4NTJFs1evr1kiza/XzT2qymzZs9fvmJVXv26Dett
3rTLdu1bZmQUd96BXa857ZoHijkoxjRHrKkTV52UQ1bmnRf1OLuyx9Oq+b67pNq/anWtmr/el5Fx
Us8b/rFhwlw1ogNU7UQjcf7vquIXbI775omhL434cur6LQ3rHd69/2EHdssqspZz+ckvvzN6oo8H
IYRw8G699xn0buWO4aTDMlN8YpeveGzQWcesv79/rw2VaFSN6ABVWeKmTk7r13PPoo8YM+mw83Y8
buBjqdKMEBYt+feQQ87Z9sjn3iwy/8r62x99OFjrtkq/kDP1uou3Pkn9Od62TbdOG1N0gKosYVMn
9evefF5R7Xn5V9132+P5BcX18+2MYy7tvvOTN27RLN0Re+x49IHPDS+ii3hXiKTu0VUnlfjK27Q+
99g7/l2uVy3XV7Brp+3apto/eOR7n/7wY6P6qRKTj8dvqEBXdnSAqi1hFY2L+xd1RciS5Yeee/Nj
xacZa7w3ZpcTR4xO337FKT4erHX1aRVzY7iySXcdyaB38/IHp7w753GHbMgqQ+VGB5BoVJhG9S88
MX1r7srDzx8+qjT9zVt46Dkjx6Zr3Xnb/Xf1Adn4LF6aam/Den/9Q2WNqGaN4w5JtX/0xFnzQnjh
rVRtTRseutfGER2g6icahcnZBvQq6jmrZ97w7ujS9rhiZe/zU6/lCCGEU/sWcW5Ryv4ey9dnxY+n
vOOu6q+cwv3Ppu7w90fu0L5yInHonps2StXl82+GwlA47IPlK1K1DugVI7ZVLzo2m62qb4mqaJzW
L33bk0Mff7UsfS5actp1hWl+AO63q/tpbHw++eLtT1Ltz8q84+LKGdGAw1Pvf/aNEEJYvmLYh6la
D+/esN7GEB2g6lc0EmPXjttvla5t6fJL7ixrv++PffSVX+7JL/ho3LUP7nVym8Py8n1ENjZbNLvw
9oKU63wO2q3Pvht+PA3rHd491f4xX34zY82/Xkw5eVK71rE9qn90gKovQVedpP5xu8a9T8+eV/ae
b3/8lL5r/jV9zusfDvtg+KhFS4o9yWPiq+krN2/82aRHXzm1X6q22y58beTqvDJ/Lsrk2B61U95s
/+nX1/Y46J3VeamWfvbv9eBzFR3WqhYdQEWjAqVf3LY6729PlafnCZOHfTBk5AW3bndEm0N/f91z
w0uQZlBtNWscwpV/X7IsVdvWrc87fkOPJ93EyTOvr/3XoiVvfJTqiL12at+yukcHkGhUmEb1d+2Y
ru2Nj2bNK1/vPc/ude7dT6RfFsrGlWjMXXDjI6lbrz499cLMWNq33LNzqv0fj58y6+f/e2po6rNP
6lW9owMkI9FIyKrVLh0y0yZFz75eCSMqSuVcdRJnRIXV+JVTp7T1QmEovPPfU2enam2Q89ezNuR1
FenqGU8PW/eol95esTLVUf17VXRsq1Z0bDabq04q0E4d0re9/qGMkYpSPyeEEFauujTN8uLTjtxh
6w03mtQ1icLCnydOQghhybIhKW/b1b5V6npIdYkOkIyKRlISjW3TtUyeOXu+LyQV9qu07v/qZG+M
HJOqPSvzrg32HJy9d26XcpXF+2Nnzv3lnnSTJwN6V9/oAMmQmKtOtmqVruXTiZXyHjbss05cdbLB
Xrl2rbVnXnDLJ09kZKx/xAHd+u738tul/DqVaTxFTpz8wqvvLF2ek+J2dr/pcd7AVasrLqxVKTpA
MiSmopH+8WcTp/gyUnF+vlB09ITHB6U+5raLatWMP5LatY5JeSeM/IJnX//1vtyVr4xIdWyj+ofv
Uz2jA0g0KnaYmZs1Tdf27QxfRipO1jrfE1fcsyw31TFbtT7vhPgj6btf6nt7jvhk7oL1926YyZOq
Ex0gOYlGItasNm2Q/mbgc+ZXypiK4qqTZLxysWfOnnfzP1IfctXpmzaMfV1F/zQTJ0+9luroYe//
8GOqow/r3qRBnKfIVG50bDabq04qVN066dvmLZQvEsttj82Yk2p/g5zrz437yps26rl3qv2r8154
M9X+VatfTLm/Zo3jela/6ABJqmgkQp3s9G2pn10JFSF35WV3pW459cgdt4n5yicclrqK9/oHCxen
qXSkmTzp37v6RQeQaFSw7Frp21au8mUknieGfPR5qv1ZmXddGvN1B/QpXToRwlujUlf3dtthmzbV
LTpAkhKNRMzwZBWREBUUVNKo0qmsPkOUEVXnVy7huRfeXJjy2P279ds/Viw6tttlu1SdrFj58lvp
zsnPf+71NDWNw+N9FisjOjabzRqNCpf6BstruJSOuD76/MnXUrfcdkmsT1+6esbgd1M/0Ox/1Y40
4zypd6o7XiQ3OkCyKhqJkFtEolHUtApUhMvuTP0JbN/q/JOifFtmnpjmcWjpJ05CCGHkmF/fMXSN
LTfvvkv1iQ6QtEQjEYWXFUUs+GxYr9pc3lq+Pit+PKZO/rfN+O62R1MfetXpzRqVqNdSva8DurVs
nqqTpcsHjyjqvMKCZ4amrZBEm8bb0NGx2WymTiJYsCh9W/Mm8kViu/mR2fNS7a+fc/15Ff9q6SZO
Xn6rqNpeCOknT47ukV27ukQHSFpFIxFyV6a7pK+om5NDRVmWe8XdqVtOPbLzOg/8K6yAZ3bUrXPE
gaVLI372yfhvpqfa3yCn7/7VIzpA0iTmoWoz5zZukLplu3bV5qFq5etzQz/mLfmvXFia/Y+/fM4J
u3ZKkatn3nXZ/r9b+3/5+Wn7LHEkjjwo1ePRQghh0L1lD1X/3k+/ViGxreToAEmTmIeqTZudrqVj
+yoW0jLHdJO09z/1l2DlKyy8cGDqlv26HnHQ2n/n5Zf/ldJNnJTPIXs3a1wdogNINCIZ91W6ll23
//mJkhtOQdpf/Q1yytpno/rpWtyUrCoY+emzw1K33PbHtRdylv+R7Fs0P2C3GKOvkXV8r+RHB5Bo
RPPphLR1gOxdt9/w40l/Z4+G9cvaZ7rJIbdZryouvT11yteu5QUD1vxr6fLyvsaJh2dG+q6Mdyvy
DRcdIImJRkIujxn9Rfo30Xf/DT+e3LS/+st+ue2mjdL1uXS5y1sr8/LWtdvUmXf+M/UpV57evHEo
DIVLlpY3EvHSgS6dOraLeZfaDREdm83m8tZops5Kv0rjmEPKnW9lfvjkvVd326HkZyxekq6lVs22
Lcs2iq5pX3/WXDlx1XDjQ3MXpNpfP+f680MI4cdl5et/l47bbx1v9P37JDs6QDIrGokx+J10Le1a
HbJ3+fo+usfunc86ftTTE1+9/PRWm5XkjNSPx15j985lGUPrFqlv0rQmzfJRrRqWLLsqzYWcpxy5
U4cQvv+hfP0P6Btz9Cf2zsxMcnSAZCYaiSm+DB6R/m1ccnJ5es4Il5++pp8O7W68YOrw4f/o37tu
dtHnTJ1ZRKKxY1lGsc+u6Xv8elol3au08u6SWpn3Ui3yrH88P/bL1FWxOy8LhfMXlCcSNTKPPyzm
t3urzfbrGvcBfzGjY7PZTJ1ENvzD9H8PHbRHz+5l7/kPx+3UYd0fiQfu/vjNc0Y+dtMBu6d/FNWc
73/4MV1bv4Oysko/ijOPTd826jM5cVVRUHDhTalb9ut25MHzy/U3+yF7N4t8n9u4FZO40QGSWtFI
jFWrH3sxfes9V9atU7Z+W2428OL19+Zs8tt+bz76yn1p/wAr/GRcurbWLfqU+i6MXXfYK+1jr76b
n359ChveiI9fejN1y61/XLKsPJdwpk8DVq1euao0W0FB6n6O6rFJdlKjA0g0onvomfQ3rtq6zf1/
KUuf2bWfur1e3XStRd1L8YMx6dsuPrl0j+XOyLju3PStQ9/zQa1aLrkl9S/Mdq3O7//d/LL22qBe
nwNStyxeUn/X7M6l2dI95ixnkyMOTmZ0gOQmGgma5/l66vOvp38r/ftce07pV2c8PjB9JWHqrKcH
pz/3lbfSj2WvXc7vX5pxXPTboqZ+nnmtWl9kmqDLW9du3077279Tn3rlmavzyjqe3/RM9+CzF95Y
ubJ0kXliUPrvk5hrNOJFx2azWaOxQVx1V34RNzG+5uzrLyhNJaFO9pO3H9MzffvVd6f5sRhCCGHM
hMkz0rcOvLjktxHbr9tNF6dvnfP98A9kxFXNX++bvzDV/np1t2pd1j7TX3z65Kul7euzLyd8k7rl
oD1abJrE6ADJrWgkyqQp//dcUe1XnvnyfZs1LVlf7Vq9959ji1jjP/qL/wwquodHihhL7VpvPlay
i25/22/YI0XdRP3uxz0houpZvOSaeyq2x7Yt9+6SumXugrdGlb6/Jwen3p+VdcLhyYsOkOREI2El
mD/dOuO7ot5Q7/0nDrnklOIuTs2pc+OFEwZ36ZS+n/z8319VWFB0Lw88uTw3fQ/1cwY/eM1ZOXWK
6mGLZg9d99jAtU+CSGXRj/c/Uc0vMk3Y5a1rt4efGf91Kb7Tir8jaJ901binB+fnlT42RUye9I07
dRIjOjabLblbjaRlRouXnHz5G48WNUHSsP6tl15+xtNDnh7y0dj1n71Qs8YeOw/od0zP+sU8+mzg
Q2MmFDeWhYvv+ddlp6dvz8q69rzzBtzx6PPDJk35dVuNrK47ntj7tGNq1yr6Na64I/09SEtqmy33
61bePr6cPOf7JL1yfPn5F930+j8qrr+T+pa2NlG0yTM+/rzbjqlaOnfYcdvPJyUrOkByZYRtkjfo
a8+75uySHLdy1ZgJ30yfPnvJstwVdbIb1m/ScMdtO3co7ld7CCG8+8kBv80vwYRF3TpfDm1ZgjuJ
zpr73n9nzV2waMGiWjWbNGzSsH3r7rumv9blZ6M+2/O4dBcqrvcLeei2bePF/OTLH3shSa/8h788
8GTZIrZgUdMSPz311Qd77VeyI7ufMHJ0Ue177vz+U6lbpsxsd2DZInf+gLuuTN1y2yN/vCVJ0QGS
rEYSB/3ne9q3PrEEj56qXWv3nXbfqfT9T5n5mwvyS7QuYlnu768a8nDxC1C3aH5cGR7RvWDRcReW
NM2gMlw8sMfeNSvke6h/+nrGq2Xt8+khd1ye+pbjJ/a57Pb8/OREB0iyzGTO+Jxy2dB3Y4Vk/sKe
p8ydX9KRDH33xgfijGN13nEXTJ1ZQesVyi9prxx9FUIoDIWTJt/3nwp4F4W1avwm7bLkJwaV9btk
zvy30ywibbHpgbsnJzo2m83lrZVg1eo+Zz41OEbPs+fte+JXU0tzxjV3/+ulGO/w6HNd1lr1Xfv3
hYvL30vvAxo3SN0y7qsvvi57v+mrIQP6JSc6QNIrGgm1Ou/Ei295uLCC/5oeM2HPYyd+W7pzCgpO
vvzfL1fsOH5cesRZr7zp41n1/bD4LxVwIWf6X/tPDCpPv88PW3859BpHHJyzSVKiAyQ90UhsMaYg
/0+3HHrq3Aq8IuGRZ/c6dtrM0o8kP6//JVffWXFJz8Rvux05ZESFXupZfqZO0mz3/+fLyeV7H00a
HLpvmlMKnxxUnu+RRYtfeyd1z5vUOeqQZETHZrOZOqlUw97boddDT1XEsrYpMw899bQrcleU9fzr
7zv4d0XdKbTklZqBD3bpt/7lsFRVefkX31S+Ho7vnW7J5Idjps0qX9/pJ0/6901GdIDkVzQSbv7C
M67eqc+gt8pzdca8BZcM7NCjvMtL3/xg+8Ou+/uPS8vxp3vh88N27nP5bWVPd6gMQ0YMK9dj72JN
nIQQwqC3lixL3bL/7iW5MLvyowNINKqA8V/1OWObg+98tCwLzz794oyr2+x7+yMV8fjq3BV/vnvL
/a65a2oZ/gr9YfEDT25/2NHnlGfpH5XlohvLXlXbtm3XHVO35Oc/+1r5P5MvD0/zrZ95Yp+qHx0g
+WpEn2HfQL6ddtENlw7s3rXvQYd037Zd8Xe2yM//ZNxr77wwbPxXFTuOHxb99e/X37tP1yN6HLRX
p61LcsaUmcPff+2dISPSLdsrsfhrJZL1yoVl7rfU72fC1w8+ddaJxbxWml4HHJHulOEfzKuAFUhP
vJLunqP9+938YFWPDpB8GaF99XtT9XO6bL9Lp7atWm/eqkWThpvUqVM7u3ZB4cpVS5bOXzhn/rfT
J00ZO+GTz5flxh5H86Y7d9yxQ4d2W2y2ebOmjTapk127Zo1Vq1eszF3x/Q/fzZs196sp4776bGLR
z24BAIkGAEAKNZQsAYBYMoUAAJBoAAASDQCAtazRAACiUdEAACQaAIBEAwDgJ9ZoAADRqGgAABIN
AECiAQDwE2s0AIBoVDQAAIkGACDRAAD4iTUaAEA0KhoAgEQDAJBoAAD8xBoNACAaFQ0AQKIBAEg0
AAB+Yo0GABCNigYAINEAACQaAAA/sUYDAIhGRQMAkGgAABINAICfWKMBAESjogEASDQAAIkGAMBP
rNEAAKJR0QAAJBoAgEQDAECiAQDEZzEoABCNigYAINEAACQaAAA/sUYDAIhGRQMAkGgAABINAACJ
BgAQn8WgAEA0KhoAgEQDAJBoAAD8xBoNACAaFQ0AQKIBAEg0AAAkGgBAfBaDAgDRqGgAABINAECi
AQAg0QAA4rMYFACIRkUDAJBoAAASDQAAiQYAEJ/FoABANCoaAIBEAwCQaAAASDQAgPgsBgUAolHR
AAAkGgCARAMAQKIBAMRnMSgAEI2KBgAg0QAAJBoAABINAECiAQAkmKtOAIBoVDQAAIkGACDRAACQ
aAAA8VkMCgBEo6IBAEg0AACJBgCARAMAkGgAAAnmqhMAIBoVDQBAogEASDQAACQaAIBEAwBIMFed
AADRqGgAABINAECiAQAg0QAAJBoAgEQDAGB9Lm8FAKJR0QAAJBoAgEQDAECiAQBINACABHPVCQAQ
jYoGACDRAAAkGgAAEg0AQKIBAEg0AADW5/JWACAaFQ0AQKIBAEg0AAAkGgCARAMAkGgAAKzP5a0A
QDQqGgCARAMAkGgAAEg0AACJBgAg0QAAkGgAABuQ+2gAANGoaAAAEg0AQKIBACDRAAAkGgCARAMA
QKIBAGxA7qMBAESjogEASDQAAIkGAIBEAwCQaAAAEg0AAIkGACDRAACqAzfsAgCiUdEAACQaAIBE
AwBAogEASDQAAIkGAIBEAwCQaAAAEg0AgCK4MygAEI2KBgAg0QAAJBoAABINAECiAQBINAAAJBoA
gEQDAJBoAABINACAypAVMgQBAIhDRQMAkGgAABINAACJBgAg0QAAJBoAABINAECiAQBINAAAJBoA
gEQDAJBoAACUhIeqAQDRqGgAABINAECiAQAg0QAAJBoAgEQDAECiAQBINAAAiQYAgEQDAJBoAAAS
DQAAiQYAINEAAKqnLCEAAGJR0QAAJBoAgEQDAECiAQBINAAAiQYAgEQDAJBoAAASDQAAiQYAINEA
ACQaAAASDQBAogEASDQAACQaAIBEAwCQaAAASDQAAIkGACDRAACQaAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACw8fl/ozPhEISv
8I8AAAAASUVORK5CYII=
B64_MODEL
    "${B64D[@]}" > "$d/power.png" <<'B64_POWER'
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
B64_POWER
    "${B64D[@]}" > "$d/accel.png" <<'B64_ACCEL'
iVBORw0KGgoAAAANSUhEUgAABDQAAAIwCAQAAADTpvPdAAAqeUlEQVR42u3dd5wU9f0/8M8Bd0fv
TZQuiIiKYgEVu1HUKBi70WgsMdHEGn8majRGE7ugfqOxx4YagURRoyhGrCggKAooICBNQHrnuP39
QeB29/bK3u3c3ZLncx8PH87slM8MO3uvfc98ZnLCswEAIBJ1QsxOAACiUcsuAACioqIBAERGRQMA
iIyKBgAgaAAA2cepEwAgMioaAEBkVDQAgMioaAAAkVHRAAAio6IBAAgaAED2ceoEAIiMigYAEBkV
DQAgMioaAEBkVDQAgMioaAAAggYAkH2cOgEAIqOiAQBERkUDAIiMigYAEBkVDQAgMioaAICgAQBk
H6dOAIDIqGgAAJFR0QAAIqOiAQBERkUDAIiMigYAEBkVDQAgMioaAICgAQBkH6dOAIDIqGgAAJFR
0QAAIqOiAQBERkUDAIiMigYAEBkVDQAgMioaAEBkVDQAgMioaAAAggYAkH2cOgEAIqOiAQBERkUD
AIiMigYAEBkVDQAgMioaAEBkVDQAgMioaAAAkVHRAAAio6IBAERGRQMAiIyKBgAQGRUNACAyKhoA
gKABAGQfp04AgMioaAAAkVHRAAAio6IBAERGRQMAiIyKBgAQGRUNACAyKhoAQGRUNACAyKhoAACR
UdEAACKjogEAREZFAwCIjIoGABAZFQ0AIDIqGgBAZFQ0AIDIqGgAAJFR0QAAIqOiAQBERkUDAIiM
igYAEBkVDQAgMioaAEBkVDQAgMioaAAAkVHRAAAio6IBAERGRQMAiIyKBgAQGRUNACAyKhoAQGRU
NACAyKhoAACRUdEAACKjogEAREZFAwCIjIoGABAZFQ0AIDIqGgBAZFQ0AIDIqGgAAJFR0QAAIqOi
AQBERkUDAIiMigYAEBkVDQBA0AAAso9TJwBAZFQ0AIDIqGgAAJFR0QAAIqOiAQBERkUDAIiMigYA
EBkVDQAgMioaAEBkVDQAgMioaAAAkVHRAAAio6IBAERGRQMAEDQAgOzj1AkAEBkVDQAgMioaAEBk
VDQAgMioaAAAkVHRAAAio6IBAERGRQMAiIyKBgAQGRUNAEDQAACyj1MnAEBkVDQAgMioaAAAkVHR
AAAio6IBAERGRQMAiIyKBgAQGRUNAEDQAACyj1MnAEBkVDQAgMioaAAAkVHRAAAiU+MrGrHbq3Pt
Of/PRwQAKk5FAwAQNACA7JMTTrMTAIBoqGgAAJHRvRUAiIyKBgAQGRUNACAyKhoAgKABAGQfp04A
gMioaAAAkVHRAAAio6IBAAgaAED2ceoEAIiMigYAEBkVDQAgMioaAEBkVDQAgMioaAAAggYAkH2c
OgEAIqOiAQBERkUDAIiMigYAIGgAANnHqRMAIDIqGgBAZFQ0AIDIqGgAAIIGAJB9suzUyeA+l+0S
wstzTxxT/nmObTdwpwNbta3XOHdtwZw145a+NOe1+bFI5vz46P1blPTeoDH/nFvyXG8vPHJ0eben
4mtJHLN+86L1E5YNnfXSd4WxzO79C7o+sn/J785e0+lfqcbfsud1u4WQO7QgVva/y4k7Hdiqbd0m
eesKZq8Z+8NLc95YECvXXrtqwj1Tk99Zf3p+rR+/O3KeLwOAaIJGFqlb++zOIYRw3I7t6s1fV545
ejZ5ql+f5luHGuf2atqr6bldJi47+6PJy6OaM3v2ZocGHRoM3GnMohPHLN8Yxd6Pwp7Nnuzbu9nW
oUa5vZr2anp+1wlLzx87cVnZc/9xjxfnzF3rsAdQ0Ujp5PbN8yYvX7npgFbndvnz5LKnP6jVq4c1
zg1h2Jyhsz9ftmJTm7q9mp7deUC73s3eP+qwUZ8ty/icsRDeXTTw3VRvrSkocU/H4v5bHhVey+iF
R2+rm+TktK3bo8kVPQa0O7j1cwcc+04m9/5TM1+as/X/a+csOTmE27+67cutYwpjJbRx634oZU8c
tcOIgxvUiYV/zH5xzufLlm9smrdHs9M7/qTD3s0/OOqEd99eWPpeK4g1rDOkz0/GpHzXRdEAKhoX
7RzCi3OWbTyg1fld/zK5rL8Mber+o3/j3FWbfvLeqAVbxixa/8XyobNO7vD3fk1ynz+o16ubCjM9
ZwgFheWpDlRWxdYSC3GnJWLfrf1u7agFD+53cbcB7fZuPmFp5vb+xsKN21pXJyeEENZvzsRe6dTg
hYMa1Plhw8B331+8ZcziDd+sGjbn8LbDD26S+1L/Xq/OK7Va8fA3v+x+Uvtj270234EPUFWy6GLQ
XZv0bx0Lz3z7/KxNhV0aHt62rOmv79W2XghnfbA1LGz10pxrJ36+/MU5jepkfs7sc/eULRWcTO/9
KNzau1ne5tiJ22LGVqMXnjwmFprm/aV36fNPWvbo9BAe2LdebQc+QNVVNLKmZHzRziH85/tvV4Uw
ct6g9hfu/PaC0qZuWOfnXUN4ff4rKS6OvH/q/VOjmHNb4aAiYhFPX8Jc89eGEELT3LKWl97eT7He
WGWnbFfvtI4hPPvtB4uKv/fWgpdmn9Lx9I5XjV+8vuRF59e6dsKg9p0bXt/ruolJ+8SpE4D/9YpG
3drndAnh4W9C2PLfgTu1yC9t+gNb168TwuPT019TxefMRl0ahhDCgnWZ3ftROGKH2jkhPD4j9buP
Tg8ht9bRO5S2hLxaSzdeMyGEq3v2aOzQB1DRSHByh+Z5P2wYMSfEQnhz/qzVnRqe3XnwlJKn36d5
CCG8vyj97av4nNlY0fjdbiFsjo1aUPry0t37FWpvGReD7ts8hILY2MWp3/9wUWGsVk7vZs/MLHkF
OSHEnpz+864HtX5w/8PezMj+BKDMoJElLuoWwt9nbNgcQgiFscem/6n3BTuX9qeuVd0QNhUurEA3
zIrPGUIIR7SNnV187K1fXD8xo7/uM7CWNnV3a3ptr6N2COHBr2etzuzej0KruiEsXr9+c+p3Vxcs
29gif8f6ZaeZX42dcPyhbc7u8vRMhz+AoPFfPZr0bx3CI9tOZzw2/cY9d2var9VHi0uao2GdENZu
rsi6Kj5nTZc6njw548pxmd77UWiUG8KagpLfX13QIr88l3l+sXzwlKt73tXnlblV0T8IQNDIipLx
L7qF8N6iqcu3Di9YO3LuwPYX7vzRopLmWFcQQqM6ObH0N6/ic4YQwjsLj327+NiCwjL2c5oXI1Zs
LbFQdA/QnFArJ4SHvv77jI8XZ37vV2L7SpxyXUEIjUu5aLVxbqn3Edm69BDCTRNP77RT/dv2uvjj
iu5/ALarikZ+7bO7hNC/deycxPGndrrs01WbUs/z3ZoQauV0aTRjVbprq/icIYRQGFtfBdWQiq1l
9IIjR239/97Nxx1XO2fOmrJjRkX2fhRmrwmhZX7j3JUp19kkr2leCGWdAtpiTcFlnww79MJuT0wf
u8RXAICKRji5Q4v8WNiY9Kc1t1aDOmd2+tvXqef5bGkIIRzedsbKdNdW8TnjfzVHPlcl1zLxhwen
XdrjD3u8NOublZnf+xVqbxkXg45bEkKtnP6tX035NJd+LXNCCJ8uKXU925Y9fPbr8wbs+FDffUZu
3lK5UtEAiEhWdG/9RfcQHvum7jOJr3u/CuGC7iXN8973KzeF8KtdclK816DOR8de0bOk8/kVnzO7
XP/Z9+vq1v5bvyj2fhTenL9h85bWpHLeziGsLnir3Pf8vHTsus29m/961xAKRAyA/+2g0aNJ/zYh
PFusj8Bz34awT4s9m6eea/3mh78OoXfzy3sWf++2Pn1b3bNv5ufMLis2XjM+hMPa/rxb5vd+FJZu
eGZmCD9u/+P2xd87tO0pnUJ4aNrqgvIubeaqv3wRws2929VfW+BrACDKoBGr6a+LuoUwd82Yhcnj
JyyZuiKEC7uVNN+Nn329MoQ79/lF9/ixObE7+1zaI4SHv/54UebnDCGECmxjunNlaC1PTX/v+xDu
2qdN3czv/YS1hnK3r9Rpr5/ww4YQnut/dLvE8Qe0GnZoTpiy4g8T0tn+2z//emWj3MH7/vc6k5iX
l5eXVxSvGl/RyK99zs4hDP22MEWBe+jMEM7qUtKJjLUFZ7y7aH3tnIf6jRlwTtddmrSu27v5+d0+
P/HqXiG8Nf+ysSWvs+JzhlAnp2leqlej3HTnqpWT6bUUd8nHBYXN8obsl/m9H4WF6waNXrWpYe6/
jxp22KAOnRs2y+vU8IT2zxz83oDm+fPXnvafdWldILux8JKPQzilU9n33gCg4mp8r5OTO7bIT1W6
31K+/+NeTfNO7vR0CbelnvDD3i8/f8hBbfq36d+maGxB4ZApvx+/sbC0tVZ8zkPaLjsz1fhpK3qM
SG+uzi+V3IeiYmsp7otl/zf1sp6ndX56RupLLCuz96Pw3vcHvPb4gfu2PKnjSR3jx7+94Mx3F61P
d2lvzX/+29M71/WINYBIg0YNvxTuou4hfLV80g+p3pu+4pPF+7W6oNvTJT6XZN6a/q/9aMfTOvdt
1bFh3dqrNk1b8db8x7+ZWY6OqxWfs0Tp9yuJZXwtxd79w4RTO+1Q/6/9dhuxelOm937CGivd62SL
yUv3e+XoHU/p1Ld1xwb166wpmLX6w0XPz/zPwort0Ss/OXanxrlBrxOAyOSEI+0EACAadfySAwCi
UssuAAAEDQAg6zh1AgBERkUDABA0AIDs49QJABAZFQ0AIDIqGgBAZFQ0AABBAwDIPk6dAACRUdEA
AAQNACD7OHUCAERGRQMAEDQAgOzj1AkAEBkVDQAgMioaAEBkVDQAAEEDAMg+Tp0AAJFR0QAABA0A
IPs4dQIAREZFAwAQNKBsA/rGPih6XXWGPQJQ3bLy1EndvBP6H7rX3ru0b9OkQX7emnVzF3858+1x
I95dvHz7bnM2bnfV2qt7/NDEr50Y3N6P4pyc/Xru02P3rrt1bt2sUYNG9evnr9uwZv2adfOXfPPd
N3M/+uL9zzcV2NdQvXJCv+xqcL38353zm1OaNCz+zoZNT4y8/uEfVkSz3tbNHrpm0CHxY/742E2P
VV2bo93uTjt8OyxxTP9fvj+p9HmOP3DYn/NyE8ddff/dQ0tf7hb9Lvz4y7LaNPX5XToUH3vFkMEv
lDzPP249+bCioZYDivZKRbbw3OOeuC5+eHNhnYOi2rup9tSrHx5/delLvvy0ey+rfPtCGHnXcQek
M/0p1730TvUfxbt0uHjQyYft1Lq0aVave+3DO54dP9VXPVSfLDt10qPj5GdvOC/VF1QI+bkXD/rq
uf57RrHeU4/48tnEmFG1ba6u7S7ZcQcUjxlX3pcYM0p20qFlTbFrp1QxI52KxtxFUYXOqtvHR+1X
NWtq0iDbjuJmjYZcMfnZy08rPWaE0LDeqUeMe3zEbc0b+7KH6gsasex57dH1g791aVd63eHNIYft
ndm1tmzywp9e+FPLpilWV0VtrpLtTmvbBvQd9pfkmHHF4HuHlmO5IYQQBh1SVnsG9i9hU0uZp3H9
+L008ZvKbGEl5qnoclK45ze1c9JacgXbl/qPfqmq9Sjec+dJT/3mlDq1y9vYgQePf2K3ztn0Xefl
tT29sqii0bTh8HL8LqmbN/y2Dm0yt9ZBh3z53KlHVGebq2e7S3NM3xG35yfFjMvuLe2URrKdd9q9
axl/GipQP+rdLSenaOizadn/O6BXlwtPrJpjK5uO4h4d376/fZqf9U47vHKnqgZUV0Uja9x2Sdcd
y/dV9sjvMrPGZo2euWn4ba2bVW+bq367S/ej/YvHjF/ffd+L6S2l9JMn7Vruu2v6Ldtrl/ihid9s
DwfozRc1qYIQ0KRh9hzFdWq/eGuLJimLLLG161esLticer7O7R79vS98qA5Z0+tk104XnJA4Zvrc
R//1+fSNBV13/Okx/Xsn/ik8at9Rn1R2jccf9PC1O7QsZYJYWfsuE22uou2OlXfrjtz3X3fUzUv8
er/0rr8OK/dytwWNPz5acnNO7B9fmyjvMvfqlhA0EvucxNL/90s5T1R7t4Qlt2p6/bm/vb8SayrP
r41ajerHD6/fuGZd6XNs2FCxNWXi03zBCcWrYa9+8MJbY7+cOW9LyNihZe9uAw8559jEz2kIgw7p
s4vLQqE6gkaWuOKM2gnVl+H/OeOGjZtCCOHtTx/+519+de058e/+9qeVCxq1aj123bnHJY5bu75+
3apvc9Vud1mO2Pflu5Jjxq/ufGh4+kvaY+cuO86cV9K7Ayt04e3ePYr+f+Wab+dvH4fob059aPiM
eVGuoXGDxFh379DfP1hzj+Jf/SRxeNmqU37/9qfxYxYsWbDk9Y/+/OSw2/r0SJz2mrNPu86XPlS1
LDl10qDe6UfFD89f8rM/bvmC2uK6h8ZNSfzd3WmHyqwvr05izFi7/orBtz5Z9W2u6u0u3WF9Xr6z
Xn5izPjlHeWPGQWbFy2Lr2mU/Ifv0L3j/2yUb+n5ubt2Khqa9E1sO7mHRl7unb+Odg3JfU6Wr665
R3H7Nsn1jPNvTYwZW81eeOSvp89NHDegX26dAFR50MiKa1aP3j+xuHv/i6vXxr9fuPnuZ+Pfz8n5
yWGVXGec0eN2P3Pw0MLCYnsv8jZX4XaXuW2H7DXy7sSaTiz2i9v+Nrz8y61T+51xCUGjhHmOO6Co
R8v3S5PqHiWuafeu8b0QPpuWgR4koQLzZLTXyRaDDj1kryh7nSQHjRWrau5RnHh6LIQ5C0e8U9L6
lq+8cnDi1A3r7ddTDwAvL71OUkq+n8BLbydPMfL9+N9GIRzTNzNrXrH6or8cccnMedXT5urb7mQH
7/XqPckx48I/P/LP9JYSf5uqvr1KugIm/sTJW5/UK+cJq6RLQb/O5vy/8IdVa+OH7728VoRHatNG
VVPRyMSnecek+2Z8ObO0NY58f/rcKbNGvn/fC5fd8+Orep5W/+APJvl1CVVf0cgK8aX0EBb+kFwS
DWH1us+nxw8fsEcmiqSvvLfb6en+Mc1km6tru5MdtOer9zaoFz+msPCCWx97Od3lfPB5UV0oJyf1
lRj5eQPi7lI56pP6+eUMGom3H8/qPid5uX95MjFEJV8xlEnJfU6Wr6q5R3Fyf6fSY2gs1u0nPU/7
8VWX3XPfCyPfnzJr/UZf+VAdQSMLyi51c7sl3CVy0jeppkr8DVu/7i4dKnfqZMnys2444ap5iypW
ps5Em6t0u1N8S299HbjH64MbJsWM8295/OX0l7thwydfFQ2lPnlyxD7xBfZRY4tdglvCmuIrGpsK
vpyRkRMh6c9R8ZMwcZo3/utLsxfEj7n1lw3rRdW+YtdorKq5R/GKpGrL7l3r5SlMe3k5dVJpPTol
Xque+kTGjKTfR726VnyNsfD8mz1Pe+6N6m1z1W93Kv12f31Iw/qJMeO8m58cWZFlNaj3+odxv3D7
NGtUfJr4OseXM+cvrleuikatWnvsXDQ0ZVZiCT77NKx37f/FD7dtce3PsruikZlP8/dLE4dbNPnd
uX4vQk2vaGSB7klPvUjdD2H+4sTh8t0YKLUNG8+4fvGy6m5z1W93cX17/fu+Rkkx49ybn3qtYkur
lx8fNOrU/nGxG43n5MSPe+PjEMrXqXiXDvHTZfcVGiGE0LLp829+PDl+zFVndWgbzbqS7wu6YnXN
PYrHfZU8xw3n33154mk9oGbJiht2tW2ROLxkeapWL0r6rdOhbeTbFou2zVW43SXcUmq/3d64v3FC
YX1z4c9ufPbfFV1u3bz3Plu8rNW2e62edNhTrybXT+K3+t8fhljSWfoS+mckXgr62dRy3BCrRt+w
q3GDELvino8ej993t196xnVlLLlC7StW0VgZYm2anzXgsD69dm7ZpE6dxcsWLf30qzc/HvXJ6rXV
fRQvWvrZtMR/6xCuPPP0o/42fNjo0i8MBVQ0StGmeXl+cSWPTf5iy742V/d279vzzQeSY8Y56cSM
4rm2diz25tii4R/1Tf4tOvDQov9fs27MZyGUr7/F3ttRn5MQQqiXH8LHXzz/Zvy40390wB5RrCsx
aGzYWKvWkKtmvXL35cf377RDw/p189q36bPrxT8Zfuesl6/+ab386j6KH0hxs/t2rf74i8kvzH7l
iRvPPb57hwDUsIpGFmiV9LSRtetTTbUmaWyq8//Z1ebq3e4+u775QOKfoMLCn96Q+Kcv7VxbK4TX
PzjrmKI/p8f0GzY6fooTE7q2btgYQik3Iy+xolGeoPHeIzX5M7+ljnPtAwMPjb8T671X9j0v8zci
S+zeurlw/NM9OqWarkWTOy8774QfXzFzXnUexX8feckpe/dINW+Htucef+7xISxZ/sGkDya9O2H8
lM2FvuKhJgSNLDh1Ui/pmQXr1qdq9dqk5zM0bpDhbUvV6yTSNlfndu+9y00XJd9foVat3NqVXHYs
xN74qLCwqEpx0mHD4u6m0LNL/O/Rl98tob9GCr3jgsbsBctXRvRRjGVsOWUsKSeEWAiz59/77O/O
Kxq7325nHv3s65luX2Kvk/p1U8eM//4LdR775NGXTphafUfx5s1nXvfeo61KedRhy6YnHnLiISGs
WD3603+9+/KYZSsDUI2y4tRJftJXVOrnM27eXPpc2dfm6tzue69sluKh2g9f32fXyi55yfL3JxYN
HXdQXtydEeJPnGwufHlMeZfZcYf4R4Bn/4mTIn95IrGfxW2/TveJO+UIGmk9u7Vl0xF3pX56alUd
xdNmH37xjLnl2a5Bhz1504J/P3dr6goIIGiU+GVTmLIgmlwmzcvN9jZX53anvjKibt7wO0v7LVk+
8SdLmjQ8fN+ioUFxQePd8UuWl3eJSZeCTtt+DtBVa29IeMDZTq2vPjvT62ia5sm2Dm0fv7F6j+LJ
M/Y+64EXNxWUb71nHD3+mWdvadnU1z1UV9DIgpt9JJ+kjxWW57ZIscy3JFnEba7S7S73H5kXb6tT
q8LLjYVYiA0fHX+dwUnbnmexY6v4esnw0eW/TVrSFRrTKrOFpaq6Z51sG//YPz9PuMvpNefs2CrD
zzpJUdFYvOzJV2548JohQ4ZOnlH83RMO3mfX6j2KV67+9e27nHTvs+U9LXLmMZOG9u7uxkleXm7Y
VYLkmy/Vrp1qquSxib933nowNr7kV81scyaWUVlr1yff2eDQPnddUbllzv3+07i7IZx4yNbqycBD
iy78jMVGvFP+JRYLGtuRwsKr7o0fblDvz5dkdg3JQWPt+qvvbXf0eTfd8uidT11+1+6nHn9Z8XvK
XHtudRwRib6dd+U9bY465tL7n586q+z1t2v1+v3t2/htCVUvK3qdJH9F1Un5FZU8dsPGbG9z9W/3
tNkn/zYv94Mn6iaUvS87Y9xXz7xWmeUOe3u/3bb+f+vmB+yx5aqN+Cs0Pvo8OeCUN2gsW5l48+6S
LF1ZViSrl9+4QU34/L819tX3jzuoaPjs4+5/ofiNqyr8FVA78aqPNeuO/c2YCfFjXn3/4As+eTrx
tm0DDsytk16kjebTvKngjY/e+CiEdq0O6dN/r36799o59XJDCKFtixdv73duAKo8aGRBr5PkvvX1
81O1ukHSRXLLV6WxbRXZC6WW4zPR5irY7lK3/x+jzr951ZoQfvXnx29KfOfh67+c8dnUCiz3v/ts
2Fu3/6Zo5HEHvf9ZCI0bHNKnaNzw0SVsRYq93qrZTnG/VCd9Xb6+KideHn9RairnnvDETRn4nFTo
hl2JU1x9z9H9iv6A5uTce1X/n4dQ/NLJirSvoCBn77KmmfrtdQ/cd03CZ7Hufrt9MLHmHMXzFw19
fejrIdSv22+Pg/c+qu9+vWqnqNb23X3QoelUyoBMyIpTJ0tXJH0ZpbzhcPLYpSuzvc3Vud2bCi6/
69T/t2pNCCE88fIjw5N/64+4uzIX182YG3/dwYADQwjhiP3i7wE6fHQa9YyEPgWfTdv+DtOpsx56
KX74oN6nHBVCCFX3NNLH/pl8V9B9etbEo3jt+rc/ufGhA85t96Or702+y2gIIfzmDF/6IGikkPxU
hNRXySd3uZu3KNvbXJ3bffb1Q54rGvr1HZ9+mfh+xx1evL12JT498UFij24tm4ZwdNzD4T+b+m0a
N4Xanq/Q2OqmhxIfdXbHZfl5IazfUFXrX7t+7OTEMekGzar9NC9aevfTXX785MvJ4w/Y03NRoOqD
RhZcsZp8zr1Vs1RTtUr64ps9P40+BxnvdZKJNmdkuyvYL2Leovh3N2w4+erkzqaH7Xvn5RXfZ8Pe
KhqVk3PI3iF2dL+iMcPeTmevJwWNqZV4VHsNeUx88Sl+WP6nhDuZdmp3xZkhtm59htpXjldy9GvZ
tBqO4rRea9aed+OD/0hcXl5unx76AHh56XVSzDezE4d3ap1qqo7tEoenzU4s3H7/Q8mvmtnmTCwj
U+YsPPN3yXc+uOKnZx1b0eVNnv717PjQ0r1jp7jtGP52OsuKP3WycdOUb7fP3wQPPD/9u/jh35/f
pkU0D3QvqaaROJxbp+qPiPRdOyS53a2b+30JVSsrep18M2fdhviHOe2c8rFJ3ZLGJpbQT70m+9qc
iWVkzqiP//DgLUkdKx/5w1czP5taseUNH33teUVBY9qsonemfJtOWGhYf+f2RUNfzshs996aY+Om
awYPv7touFGDWy6JP70VteROsMW7vEZ/RKRv5ZrPph7YO35M8yYBqOKgkQW9TjZvnjAl/stiz+45
ofijpRJvjr1gyXcLIm5WqSdkMtHmKtzucj1E/c+P7rfbCYfGj6mXP+KePqf/sKLcy41b6rBRRUGj
Z5ezjy+aaNhbpezZYu3as1v8XUwnTiuxt0pa/34lzhMi2rvleJLOiLffHR/fM+fnJ77w74y0r1yS
I8CiH9JbW2Y+zXVqd22/a+ddu/TssmvnZo13OTH1jcwTA1ri8KZN2fCdByoaVe4/4+K/opo03LN7
8i+dHVsnfhGO/mR7aHPN2u5Y7Jzrxw2Nrx+E0HGHF+44+pcVeUrmuK9mL+i4w9ahfXdLCBppSOpz
MnV7PlyvvGvcc0U3NatV67oLCzaXfN+I8mja6MwBrZq3bNqqWcumrZq1bLapoMtxqW4O3qhB8lNu
vp5d1UdEj87D7u7WIf6UzcDDXxpV1lq7tk8cjuJEKVCaWtnRzJFJj9fa0rkv3qk/Shz+1zvbQ5tr
2navWH3SlcnnvI/Y/44K3il0RMourN/OS69cnhg0ts8+J1tNmPLUyPjhQ/epXMwIYf3Ge66+6eJL
Tz/t6CP236N7u1Yddziuf6rpLjwp8VklGze9Oz4xsMQmJr46tcv0p3n6nDYtEq8MuePysm6pdnCf
Dm0Tx3w109c+VHXQyIprVj+eNGt+fLN/cXKzRvHvN6h7xU/j31+1ZuS7EbSj2E/8qNtchdtdzm37
4uuLbi72O/vsMwek86yTbT1PUv4aHfZWei3be9f4msukqRnsQRIqME/Gn3WS+Pr9kDXrSis6pfta
v/6TpG6rd13ZsF7yVLt0/OMvE6f6YOLqNeluY2U/zQUFyTG6847/GtK0Yclb16b5I39InGPW/Fnz
9AHw8tLrJKWHErqptWj6zJ/rbruwLLfOEze3T/jd8tiIdRu2jzbXvO1+9tUHhiaPe/Sm3rukv6QP
Jy1ckjJopCEvt2eX+GrIyjXb9y+D+YvvfDLT/56Jw907vvVwl53ixxzZd8wTDesnTjXk2eo4Iu54
IvmajEP3+fyln52QqgdM7VpnHTduaPeOiWOfGenXJVS1OtnS0L/945pz468XP7b/VyMeGzF5emHh
rl3OH5T4dbJuwz1PV25tgw5/pNiDsOsl3Rz5mvMuPT1xzD9G/fKWTLe5are7fK68q0/Pfnsm7Jv8
EYP3OeOH5ektp7Dwn+9cfEryH9KxX6SzjN26xj9IfPs+cbLFnU9e+JMdW2dueU+98qdLWzWLH7P/
7lP++dp7YybM+z43t1O7AQcl9toIIYSxX1TsFF1lP83TZj380q9OSxzXvu2Tf7rv2tFjJ30947sV
q9dvyM9r1KDzjrt3O6pv8f4lK9fc91wAqjxoZMkV2MtX3vDA/12XWDa95dLU097+eGV7nOTntmha
1jT18uM764UQQqP6iXszE22uou1Oq0/Gpk2nXDX+hTYt4sd1avf87cdcXOyi0DL6bQwblRw0hr8V
KyyjpQlLSLoUdEqJrc62Xiclrmvtut8P+fut5V5Tmdat/92QR29KrhMNPHzg4SXOseGSW8vV/ljm
P83XDj5orz26J49t3KC09ha56s7FS33pQ1WrlT1NffDFNz4sz3Qff37rw9tTm2vids9bdPo1yaHi
yL63XZ7ucv7zafITMNI7cfK/dSnoVk+PHP9VJpf32PAX30gjNcXO+X3F11/ZT/OqNcddUtHbkg9+
5tHhvvJB0Cj1C+70304ss/PitFkn/qbsvvXZ1Oaaud3/+fTawcnjrj739GPSW0rB5pf/Ez+8ZPl7
4ysVNKb+Lxy0sdiVd2Z2iedcV96At37Dz/9QdpfSKI+Iud/vc/o7aXfiLiy8/v4r7vCFD4JGGZav
OvyC0n8PvTuu/88WLd3e2lwzt/uuJ4v/wXns5j3TvCg08Q/cP0end0eOnJz49f2wfO73/xuH7Zjx
w9/K5PI2bDz16hv/WvYj2r6e3fenT/6ruo+IhUuOvOiKO1JdSFySTyb3++mtj/i6h+oKGlnVSWbZ
igEXX3DjdwtTbcr8Rb+65fDzFy+NpCNruX+wRdPmKtjucm1L4uvnN0xNulV4/bojBjdvnE6nzVEf
rorrJzJ8VHpdQ7u1j+8NMXFaxjurpj9Hph6qVsYSr7kn+Y6XlWpfrHDzzQ/2PPHxEatK7LUzefrP
rus1MBPdhyv/aS7cPPjpzsdccuuY8WVV8VavffGNH120/xmffKGLoZdXdb1yQq/sS0d1ah9z0LH9
+/TsslOTRiGsWPXtvAlTXn/vtfdq8lMuMtHmbNzuaJ12zPNxJxHu/vvVd/ntUDn16x578P67771r
px2bNGzccOOmpSuWrvhm9nsTxoyfNC0Wq3lHcbPGh+/fa+cenbt3atGkQb2G9fPzNhWs27B0xYLF
M76bPH3s5x9NShnIgCqUlUEDAMiS4oAHDAEAUallFwAAggYAkHWcOgEAIqOiAQAIGgCAoAEAsI1r
NACAyKhoAACCBgCQfZw6AQAio6IBAAgaAICgAQCwjWs0AIDIqGgAAIIGAJB9nDoBACKjogEACBoA
gKABALCNazQAgMioaAAAggYAkH2cOgEAIqOiAQAIGgCAoAEAsI1rNACAyKhoAACCBgCQfZw6AQAi
o6IBAAgaAICgAQCwjWs0AIDIqGgAAIIGACBoAABs4xoNACAyKhoAgKABAAgaAADbuEYDAIiMigYA
IGgAAIIGAMA2rtEAACKjogEACBoAgKABALCNazQAgMioaAAAggYAIGgAAGzjGg0AIDIqGgCAoAEA
CBoAANu4RgMAiIyKBgAgaAAAggYAwDau0QAAIqOiAQAIGgCAoAEAsI1rNACAyKhoAACCBgAgaAAA
CBoAQPRcDAoAREZFAwAQNAAAQQMAYBvXaAAAkVHRAAAEDQBA0AAAEDQAgOi5GBQAiIyKBgAgaAAA
ggYAwDau0QAAIqOiAQAIGgCAoAEAIGgAANFzMSgAEBkVDQBA0AAABA0AAEEDAIiei0EBgMioaAAA
ggYAIGgAAAgaAED0XAwKAERGRQMAEDQAAEEDAEDQAACi52JQACAyKhoAgKABAAgaAACCBgAQPReD
AgCRUdEAAAQNAEDQAAAQNAAAQQMAyGJ6nQAAkVHRAAAEDQBA0AAAEDQAgOi5GBQAiIyKBgAgaAAA
ggYAgKABAAgaAEAW0+sEAIiMigYAIGgAAIIGAICgAQAIGgBAFtPrBACIjIoGACBoAACCBgCAoAEA
CBoAgKABAFCc7q0AQGRUNAAAQQMAEDQAAAQNAEDQAACymF4nAEBkVDQAAEEDABA0AAAEDQBA0AAA
BA0AgOJ0bwUAIqOiAQAIGgCAoAEAIGgAAIIGACBoAAAUp3srABAZFQ0AQNAAAAQNAABBAwAQNAAA
QQMAQNAAAKqQ+2gAAJFR0QAABA0AQNAAABA0AABBAwAQNAAABA0AoAq5jwYAEBkVDQBA0AAABA0A
AEEDABA0AABBAwBA0AAABA0AYHvghl0AQGRUNAAAQQMAEDQAAAQNAEDQAAAEDQAAQQMAEDQAAEED
AKAU7gwKAERGRQMAEDQAAEEDAEDQAAAEDQBA0AAAEDQAAEEDABA0AAAEDQCgOtQOOXYCABANFQ0A
QNAAAAQNAABBAwAQNAAAQQMAQNAAAAQNAEDQAAAQNAAAQQMAEDQAAMrDQ9UAgMioaAAAggYAIGgA
AAgaAICgAQAIGgAAggYAIGgAAIIGAICgAQAIGgCAoAEAIGgAAIIGALB9qm0XAABRUdEAAAQNAEDQ
AAAQNAAAQQMAEDQAAAQNAEDQAAAEDQAAQQMAEDQAAEEDAEDQAAAEDQBA0AAAEDQAAEEDABA0AAAE
DQBA0AAABA0AAEEDAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAgP89/x/OOyO+zyefRgAAAABJRU5ErkJggg==
B64_ACCEL
    "${B64D[@]}" > "$d/topspeed.png" <<'B64_TOPSPEED'
iVBORw0KGgoAAAANSUhEUgAABDQAAAIwCAQAAADTpvPdAAAlwElEQVR42u3dd5xU1d0/8DvL7tJh
6SBdUQELKIooSjGxxgIYY28xMSbGGDV5YsRYf9YY9YnRiBo1Ro1GUWOMWFCwoGJBbCBYEBTpVerC
7v7+8AF35t7ZfpCB93tfryRz5t47d84ymc9+z7nnpqL7IwCAIPKjMp0AAISRpwsAgFBUNACAYFQ0
AIBgVDQAAEEDAMg9hk4AgGBUNACAYFQ0AIBgVDQAgGBUNACAYFQ0AABBAwDIPYZOAIBgVDQAgGBU
NACAYFQ0AIBgVDQAgGBUNAAAQQMAyD2GTgCAYFQ0AIBgVDQAgGBUNACAYFQ0AIBgVDQAAEEDAMg9
hk4AgGBUNACAYFQ0AIBgVDQAgGBUNACAYFQ0AIBgVDQAgGBUNAAAQQMAyD2GTgCAYFQ0AIBgVDQA
gGBUNACAYFQ0AIBgVDQAgGBUNACAYFQ0AIBgVDQAgGBUNAAAQQMAyD2GTgCAYFQ0AIBgVDQAgGBU
NACAYFQ0AIBgVDQAgGBUNACAYFQ0AIBgVDQAgGBUNACAYFQ0AIBgVDQAgGBUNACAYFQ0AABBAwDI
PYZOAIBgVDQAgGBUNACAYFQ0AIBgVDQAgGBUNACAYFQ0AIBgVDQAgGBUNACAYFQ0AIBgVDQAgGBU
NACAYFQ0AIBgVDQAgGBUNACAYFQ0AIBgVDQAgGBUNACAYFQ0AIBgVDQAgGBUNACAYFQ0AIBgVDQA
gGBUNACAYFQ0AIBgVDQAgGBUNACAYFQ0AIBgVDQAgGBUNACAYFQ0AIBgVDQAgGBUNACAYFQ0AIBg
VDQAgGBUNACAYFQ0AIBgVDQAgGBUNACAYFQ0AIBgVDQAgGBUNACAYFQ0AIBgVDQAgGBUNACAYFQ0
AIBgVDQAAEEDAMg9hk4AgGBUNACAYFQ0AIBgVDQAgGBUNACAYFQ0AIBgVDQAgGBUNACAYFQ0AIBg
VDQAgGBUNACAYFQ0AIBgVDQAgGBUNAAAQQMAyD2GTgCAYFQ0AIBgVDQAgGBUNACAYFQ0AIBgVDQA
gGBUNACAYFQ0AIBgVDQAgGBUNAAAQQMAyD2GTgCAYFQ0AIBgVDQAgGBUNACAYFQ0AIBgVDQAgGBU
NACAYFQ0AABBAwDIPYZOAIBgVDQAgGBUNACAYFQ0AIBgNvuKRtm13+Wrp37nnwgA1JyKBgAgaAAA
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
Mxcmj6IWzer8d1HWqe342+M1niiaMfum++vw1cqisiga80p60Djqezfdn77Zvn3TF1p/6pV166Io
8U4lZVUOGpvu36+hE4Ca/DG6pbyRc0/48/8ktf/mxkWJy3DV/Cbxndv956b42g9Jq0EUr8t+lPgd
WRoU5tXxb6NNi/F3JMWMKOre8a8X1vVv4LmJa9MWVt9n13YZs1aGZQycPDaueq/QvEn3jjWvaAAg
aNTYNb+64fyk9nueuOvfyXvUPGhE0W49LzszFjQK4ttVdPvy9SXxtoI6HsjaoWtyzIiiKDrtiF8e
U7ev9vXK5yam/dPKy7yUNf3xmuKnXqluv6c/XrVm+iwfYYDN2xYwdNKg8G+XHn9I0jOTpv78ymzv
L35x67fWFs+ev2hZy+ad2mZbtfLcE257+POvKg0aJdl7tyQhaBTmZ1vgqwqq/Xu88TfvTX9pUh29
UlkURdHoselzMEbsP+qRbx/13TH9OpunJ6xcVfHxYkEjY+DkvY9LS+qqN0L0MABbQEWjXatxdybH
jCmfHfLLzLukVl7RGPfm8POa77fd4f1P7HF4y8HDz5s0NWmrwoLzTkpvqc6UxqzfZJv0qyy/3iPX
d25fl0d84sX0Os3QPcv38vD907ce/Xx1j9/XYl0Agsamtev2b9w3YJekZ6Z9/r0z5lewYFZS0Che
9+NL9z/j8XEb5hqsWvP4uD1OuOEfSfuffFhhQfq+8W3q5VX0NR9vi8/bCKtNi8duaFBYd8dbvGzc
m+UfF+QfPujbR+kzNNat/8+L1T2+VUEBck9OD50cNuif1zRJXNdi4vtHnFNRzIiistJPM25hVhad
/6cnxserDOf/qWXzU2OXzTZvMnj3514v98WZHDSy9m5SCCkursVvo8I9p844eeSdl/bZIbO9X6/b
/3DyRXXwSv/XNnrsAQPKN4/43j+e/OZ/de+46/blnxn7+rKvq/ca9Qt7ZSzyPvmjrO/a0AnAZhM0
ctZZx/z5d8nXaYwee9LI1ZXMdnhgzANjqvpKv7r2iMEtm2e2DupXPmisSFgzo7Ag+zHjsz9WrQk1
dHL/Uz+7YuXqEee99UB8rY6TDps0NfMy1Jp7fNytF5b/nRwwoH7hN/Wh2g+c7NIjvQpUWvr+x9XZ
f9rnl1ZxufXe2/7hDP/XALCVB40rzrrop4l/dpZdeefFt9btV/bXK28ffcGPM1vTr4FIuiFbk0bZ
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
B64_TOPSPEED
}

BAND_NAMES=(model power accel topspeed)

if [[ ${1:-} == --bandes ]]; then
    printf 'Textes embarqués :\n'
    printf '  %s\n' "${BAND_NAMES[@]}"
    exit 0
fi

command -v ffmpeg  >/dev/null || die "ffmpeg introuvable dans le PATH."
command -v ffprobe >/dev/null || die "ffprobe introuvable dans le PATH."
[[ -d $VIDEO_DIR ]] || die "dossier introuvable : $VIDEO_DIR"

OUTPUT="$VIDEO_DIR/$OUTPUT_NAME"

BANDDIR=$(mktemp -d)
trap 'rm -rf "$BANDDIR"' EXIT
extract_bands "$BANDDIR"

inputs=()          # arguments -i pour ffmpeg
filters=()         # un filtre de préparation par clip
concat_labels=""   # [v0][v1]... pour le concat
total=0            # durée cumulée du montage

idx=0
shopt -s nullglob
for line in "${CLIPS[@]}"; do
    # Le commentaire (# ...) est ignoré par read : on ne lit que 3 champs.
    read -r stamp start end _ <<<"$line"

    # Résolution du fichier à partir des 6 chiffres de l'horodatage.
    matches=("$VIDEO_DIR"/*_"$stamp"_*.mp4 "$VIDEO_DIR"/*_"$stamp".mp4)
    (( ${#matches[@]} > 0 )) || die "aucun fichier ne correspond à l'horodatage $stamp dans $VIDEO_DIR"
    (( ${#matches[@]} == 1 )) || die "plusieurs fichiers correspondent à $stamp : ${matches[*]}"
    file="${matches[0]}"

    # Contrôle : le clip est-il assez long pour l'intervalle demandé ?
    src_dur=$(ffprobe -v error -select_streams v:0 -show_entries format=duration \
                      -of default=nw=1:nk=1 "$file")
    src_frames=$(awk -v d="$src_dur" -v f="$FPS" 'BEGIN { printf "%d", int(d * f + 0.5) }')

    # Découpe en NUMÉROS D'IMAGES et non en secondes : trim=start_frame/end_frame
    # garantit un compte exact, là où un découpage en secondes dépend de la
    # cadence source et fait dériver la durée réelle de la durée annoncée.
    sf=$(awk -v a="$start" -v f="$FPS" 'BEGIN { printf "%d", int(a * f + 0.5) }')
    ef=$(awk -v b="$end"   -v f="$FPS" 'BEGIN { printf "%d", int(b * f + 0.5) }')
    nf=$((ef - sf))
    (( nf > 0 )) || die "intervalle vide pour l'horodatage $stamp (${start}s → ${end}s)."
    (( ef <= src_frames )) || die "$(basename "$file") ne contient que ${src_frames} images (${src_dur}s), or le montage en demande ${ef}. Ce plan ne peut pas dépasser $(awk -v n="$src_frames" -v f="$FPS" 'BEGIN { printf "%.4f", n / f }')s."
    seg=$(awk -v n="$nf" -v f="$FPS" 'BEGIN { printf "%.4f", n / f }')
    total=$(awk -v t="$total" -v s="$seg" 'BEGIN { printf "%.4f", t + s }')

    info "$(printf '%d.' $((idx + 1))) $(basename "$file") — ${start}s → ${end}s (${nf} images, ${seg}s)"

    inputs+=(-i "$file")
    # trim  : garde l'intervalle demandé      setpts : remet le clip à t=0
    # fps   : cadence uniforme                scale/pad : sécurité si un clip
    #                                         n'est pas déjà en WIDTHxHEIGHT
    # fps AVANT trim : on normalise la cadence, puis on coupe sur la grille
    # d'images de sortie. Dans l'autre sens, le nombre d'images produites
    # dépend de la cadence du fichier source et la durée réelle dérive.
    filters+=(
        "[${idx}:v]fps=${FPS},trim=start_frame=${sf}:end_frame=${ef},setpts=PTS-STARTPTS,\
scale=${WIDTH}:${HEIGHT}:force_original_aspect_ratio=decrease,\
pad=${WIDTH}:${HEIGHT}:(ow-iw)/2:(oh-ih)/2,setsar=1,format=yuv420p[v${idx}]"
    )
    concat_labels+="[v${idx}]"
    idx=$((idx + 1))
done
shopt -u nullglob

(( idx > 0 )) || die "la liste CLIPS est vide."

# Coupes franches : simple concaténation, aucun fondu enchaîné.
graph=$(IFS=';'; echo "${filters[*]}")
graph+=";${concat_labels}concat=n=${idx}:v=1:a=0[vcat]"

# Incrustation des textes. Chaque texte est un PNG bouclé sur sa durée, dont
# l'alpha monte et descend (fade ... :alpha=1), décalé dans le temps du montage
# par setpts, puis composité par overlay. Aucun de ces filtres n'a de dépendance
# externe, contrairement à drawtext.
prev=vcat
next_in=$idx
n=0
if (( ${#OVERLAYS[@]} > 0 )); then
    for line in "${OVERLAYS[@]}"; do
        read -r t_in t_out band px py _ <<<"$line"
        png="$BANDDIR/$band.png"
        [[ -f $png ]] || die "texte inconnu : « $band ». Liste disponible : $0 --bandes"

        # Position : valeur par défaut si absente ou non numérique.
        [[ ${px:-} =~ ^[0-9]*\.?[0-9]+$ ]] || px=0.5
        [[ ${py:-} =~ ^[0-9]*\.?[0-9]+$ ]] || py=0.7

        dur=$(awk -v a="$t_in" -v b="$t_out" 'BEGIN { printf "%.3f", b - a }')
        awk -v d="$dur" -v f="$TEXT_FADE" 'BEGIN { exit !(d <= 2 * f) }' \
            && die "le texte « $band » ne dure que ${dur}s, trop court pour deux fondus de ${TEXT_FADE}s."
        fo=$(awk -v d="$dur" -v f="$TEXT_FADE" 'BEGIN { printf "%.3f", d - f }')

        inputs+=(-loop 1 -framerate "$FPS" -t "$dur" -i "$png")
        graph+=";[${next_in}:v]format=rgba"
        graph+=",fade=t=in:st=0:d=${TEXT_FADE}:alpha=1"
        graph+=",fade=t=out:st=${fo}:d=${TEXT_FADE}:alpha=1"
        graph+=",setpts=PTS-STARTPTS+${t_in}/TB[b${n}]"
        # Les max/min empêchent le texte de déborder de l'image.
        graph+=";[${prev}][b${n}]overlay"
        graph+="=x='max(0\,min(main_w-overlay_w\,main_w*${px}-overlay_w/2))'"
        graph+=":y='max(0\,min(main_h-overlay_h\,main_h*${py}-overlay_h/2))'"
        graph+=":eof_action=pass:repeatlast=0[o${n}]"

        info "texte « ${band} » de ${t_in}s à ${t_out}s — position x=${px} y=${py}"
        prev="o${n}"
        next_in=$((next_in + 1))
        n=$((n + 1))
    done
fi

# Fondu de sortie sur la fin du montage global. Il emporte les textes avec
# l'image, puisqu'il est appliqué après les overlays.
if awk -v f="$FADE_OUT" 'BEGIN { exit !(f > 0) }'; then
    # Le fondu doit s'annuler sur la DERNIÈRE IMAGE EXISTANTE, pas une image
    # plus tard. « st = total - FADE_OUT » fait atteindre alpha=0 à t=total,
    # or la dernière image est à t=total-1/FPS : il y restait 1/(FADE_OUT*FPS)
    # de luminosité, soit 4,17 % à 24 fps pour un fondu d'1 s. Mesuré, pas
    # supposé. On recule donc le départ d'une image.
    fade_st=$(awk -v t="$total" -v f="$FADE_OUT" -v r="$FPS" \
                  'BEGIN { s = t - f - 1 / r; printf "%.4f", (s > 0 ? s : 0) }')
    graph+=";[${prev}]fade=t=out:st=${fade_st}:d=${FADE_OUT}[vout]"
    info "fondu de sortie : ${FADE_OUT}s à partir de ${fade_st}s"
else
    graph+=";[${prev}]null[vout]"
fi

audio_args=(-an)
if [[ -n $MUSIC ]]; then
    # Chemin relatif : on le cherche d'abord tel quel, puis dans VIDEO_DIR.
    music_path="$MUSIC"
    [[ -f $music_path ]] || music_path="$VIDEO_DIR/$MUSIC"
    [[ -f $music_path ]] || die "musique introuvable : $MUSIC"

    # Le morceau doit couvrir MUSIC_START + la durée du montage.
    mus_dur=$(ffprobe -v error -show_entries format=duration \
                      -of default=nw=1:nk=1 "$music_path" 2>/dev/null) \
        || die "impossible de lire la durée de $MUSIC — est-ce bien un fichier audio ?"
    besoin=$(awk -v s="$MUSIC_START" -v t="$total" 'BEGIN { printf "%.2f", s + t }')
    awk -v d="$mus_dur" -v b="$besoin" 'BEGIN { exit !(d + 0.05 < b) }' \
        && die "le morceau dure ${mus_dur}s, or il en faut ${besoin}s (MUSIC_START=${MUSIC_START} + montage ${total}s). Baisse MUSIC_START ou prends un morceau plus long."

    a_fade_st=$(awk -v t="$total" -v f="$FADE_OUT" 'BEGIN { printf "%.3f", (t - f > 0 ? t - f : 0) }')

    inputs+=(-ss "$MUSIC_START" -t "$total" -i "$music_path")
    # loudnorm avant les fondus : il doit mesurer le morceau, pas les fondus.
    # Il rééchantillonne en interne, d'où l'aresample qui le suit.
    agraph="[${next_in}:a]atrim=duration=${total},asetpts=PTS-STARTPTS"
    agraph+=",loudnorm=I=${MUSIC_LUFS}:TP=-1.5:LRA=11"
    agraph+=",aresample=48000"
    agraph+=",afade=t=in:st=0:d=${MUSIC_FADE_IN}"
    agraph+=",afade=t=out:st=${a_fade_st}:d=${FADE_OUT}[aout]"
    graph+=";${agraph}"

    audio_args=(-map "[aout]" -c:a aac -b:a 192k -ar 48000)
    info "musique : $(basename "$music_path") — depuis ${MUSIC_START}s, cible ${MUSIC_LUFS} LUFS"
    info "  fondu audio : ${MUSIC_FADE_IN}s à l'entrée, ${FADE_OUT}s à la sortie depuis ${a_fade_st}s"
elif (( SILENT_AUDIO == 1 )); then
    inputs+=(-f lavfi -t "$total" -i anullsrc=channel_layout=stereo:sample_rate=48000)
    audio_args=(-map "${next_in}:a" -c:a aac -b:a 128k)
fi

info "durée totale : ${total}s — sortie : $OUTPUT"

ffmpeg -hide_banner -y \
    "${inputs[@]}" \
    -filter_complex "$graph" \
    -map "[vout]" "${audio_args[@]}" \
    -c:v libx264 -preset "$PRESET" -crf "$CRF" \
    -profile:v high -pix_fmt yuv420p \
    -r "$FPS" -g $((FPS * 2)) -keyint_min "$FPS" -sc_threshold 0 \
    -movflags +faststart \
    "$OUTPUT"

info "terminé : $OUTPUT"
ffprobe -v error -select_streams v:0 \
        -show_entries stream=width,height,r_frame_rate,nb_frames \
        -show_entries format=duration,size \
        -of default=nw=1 "$OUTPUT"

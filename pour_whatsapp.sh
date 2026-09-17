#!/usr/bin/env bash
#
# pour_whatsapp.sh — Réencode un Reel pour l'envoi en MÉDIA sur WhatsApp.
#
#   ./pour_whatsapp.sh cullinan_v1.mp4            # vise 14 Mo
#   ./pour_whatsapp.sh cullinan_v1.mp4 12         # vise 12 Mo
#
# Envoyée en média, une vidéo se lit directement dans la conversation ; en
# pièce jointe elle s'affiche en icône de fichier, sans aperçu. Mais le
# plafond pratique du média tourne autour de 16 Mo, au-delà duquel WhatsApp
# recompresse avec SES réglages. Mieux vaut viser en dessous nous-mêmes.
#
# Deux passes à débit ciblé, et non un CRF : le CRF donne une qualité
# constante mais une taille imprévisible, or c'est ici la taille qui est
# la contrainte.
#
set -euo pipefail
export LC_ALL=C

SRC="${1:-}"
CIBLE_MO="${2:-14}"
[[ -n $SRC && -f $SRC ]] || { echo "usage : $0 <video.mp4> [taille_Mo]" >&2; exit 1; }
command -v ffmpeg >/dev/null || { echo "ffmpeg introuvable" >&2; exit 1; }

OUT="${SRC%.*}_wa.mp4"
DUR=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$SRC")
A_KBPS=128

# débit vidéo = (taille cible en bits / durée) - débit audio, avec 3 % de
# marge pour l'en-tête du conteneur.
V_KBPS=$(awk -v mo="$CIBLE_MO" -v d="$DUR" -v a="$A_KBPS" \
    'BEGIN { printf "%d", (mo * 8192 / d) * 0.97 - a }')
(( V_KBPS > 200 )) || { echo "cible trop basse pour ${DUR}s" >&2; exit 1; }

echo "• source : $SRC ($(du -h "$SRC" | cut -f1), ${DUR}s)"
echo "• cible  : ${CIBLE_MO} Mo → vidéo ${V_KBPS} kb/s, audio ${A_KBPS} kb/s"

PASSLOG=$(mktemp -u)
trap 'rm -f "${PASSLOG}"*' EXIT

ffmpeg -hide_banner -loglevel error -y -i "$SRC" \
    -c:v libx264 -preset slow -b:v "${V_KBPS}k" -pass 1 -passlogfile "$PASSLOG" \
    -pix_fmt yuv420p -an -f mp4 /dev/null
ffmpeg -hide_banner -loglevel error -y -i "$SRC" \
    -c:v libx264 -preset slow -b:v "${V_KBPS}k" -pass 2 -passlogfile "$PASSLOG" \
    -profile:v high -pix_fmt yuv420p \
    -c:a aac -b:a "${A_KBPS}k" -ar 44100 \
    -movflags +faststart "$OUT"

echo "• terminé : $OUT ($(du -h "$OUT" | cut -f1))"
ffprobe -v error -select_streams v:0 \
        -show_entries stream=width,height,nb_frames \
        -show_entries format=duration,size -of default=nw=1 "$OUT"

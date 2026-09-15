#!/usr/bin/env bash
#
# build_reel.sh — Assemble des clips vidéo en un Reel Instagram vertical (9:16).
#
# Principe : chaque clip source est tronqué à son point de coupe, recadré au
# centre en conservant toute la hauteur, redimensionné en 1080x1920, converti
# à 30 fps, puis tous les clips sont concaténés en coupes franches (pas de
# transition, pas d'audio) en un SEUL encodage — pas de fichiers
# intermédiaires, donc pas de perte de génération.
#
# Réutilisation : ne modifier que le bloc CONFIGURATION ci-dessous
# (SRC_DIR, OUT_NAME et la liste CLIPS). Rien d'autre.
#
# Usage :
#   ./build_reel.sh                      # utilise la config ci-dessous
#   ./build_reel.sh /chemin/vers/dossier # surcharge SRC_DIR
#   ./build_reel.sh /chemin/ sortie.mp4  # surcharge SRC_DIR et OUT_NAME
#
set -euo pipefail

# ─────────────────────────── CONFIGURATION ───────────────────────────

# Dossier contenant les clips source (et qui recevra le fichier de sortie).
SRC_DIR="${1:-$HOME/Desktop/video-g63}"

# Nom du fichier de sortie, écrit dans SRC_DIR.
OUT_NAME="${2:-g63_v1.mp4}"

# Montage : un clip par ligne, dans l'ordre exact de la vidéo finale.
#
#   "<horodatage>:<durée>:<description>"
#
#   horodatage  = les six chiffres après la date dans le nom de fichier
#                 (hf_20260915_XXXXXX_[hash].mp4). Sert à retrouver le fichier.
#   durée       = nombre de secondes à conserver DEPUIS LE DÉBUT du fichier.
#                 IMPÉRATIF : au-delà, les clips générés par IA contiennent
#                 des artefacts. Ne jamais rallonger.
#   description = commentaire libre, affiché pendant le traitement.
#
CLIPS=(
  "034501:3:face avant"
  "035102:4:profil"
  "042036:4:poste de conduite"
  "040131:3:arriere"
  "041452:2:tableau de bord"
  "042629:4:banquette arriere"
  "040844:4:sieges cuir"
)
# Note : le clip 035612 est volontairement exclu du montage.

# Motif de recherche des fichiers. Le %s est remplacé par l'horodatage.
FILE_GLOB='*_%s_*.mp4'

# ───────────────────────── FORMAT DE SORTIE ──────────────────────────

OUT_W=1080          # largeur cible
OUT_H=1920          # hauteur cible (9:16)
FPS=30              # fréquence d'images uniforme
CRF=18              # qualité H.264 (plus bas = meilleure qualité)
PRESET="slow"       # preset x264
PIX_FMT="yuv420p"   # format de pixels compatible Instagram

# ─────────────────────────── VÉRIFICATIONS ───────────────────────────

for bin in ffmpeg ffprobe; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "ERREUR : '$bin' est introuvable. Installez ffmpeg avant de relancer." >&2
    echo "  macOS   : brew install ffmpeg" >&2
    echo "  Debian  : sudo apt-get install ffmpeg" >&2
    exit 1
  fi
done
echo "ffmpeg : $(ffmpeg -version | head -1)"

if [[ ! -d "$SRC_DIR" ]]; then
  echo "ERREUR : dossier introuvable : $SRC_DIR" >&2
  exit 1
fi

OUT_PATH="$SRC_DIR/$OUT_NAME"

# ──────────────── RÉSOLUTION DES FICHIERS + DURÉE TOTALE ─────────────

# Résout chaque horodatage vers un chemin de fichier unique. Une correspondance
# absente ou ambiguë est une erreur : mieux vaut s'arrêter que monter le
# mauvais plan.
declare -a FILES=() DURS=()
TOTAL=0

echo
echo "Montage (${#CLIPS[@]} plans) :"
for entry in "${CLIPS[@]}"; do
  IFS=':' read -r stamp dur label <<< "$entry"

  # shellcheck disable=SC2231  # glob volontairement non quoté pour l'expansion
  matches=( $SRC_DIR/$(printf "$FILE_GLOB" "$stamp") )
  if [[ ${#matches[@]} -eq 0 || ! -e "${matches[0]}" ]]; then
    echo "ERREUR : aucun fichier pour l'horodatage $stamp dans $SRC_DIR" >&2
    exit 1
  fi
  if [[ ${#matches[@]} -gt 1 ]]; then
    echo "ERREUR : horodatage $stamp ambigu, ${#matches[@]} fichiers correspondent :" >&2
    printf '  %s\n' "${matches[@]}" >&2
    exit 1
  fi

  FILES+=( "${matches[0]}" )
  DURS+=( "$dur" )
  TOTAL=$(( TOTAL + dur ))
  printf '  %-8s %ss  %-20s %s\n' "$stamp" "$dur" "$label" "$(basename "${matches[0]}")"
done
echo "Durée attendue : ${TOTAL}s"

# ──────────────────── CONSTRUCTION DE LA COMMANDE ────────────────────

# Entrées : '-t <durée>' placé AVANT '-i' limite la lecture du fichier à
# l'intervalle voulu, en partant du début. C'est ce qui applique les points
# de coupe.
INPUTS=()
for i in "${!FILES[@]}"; do
  INPUTS+=( -t "${DURS[$i]}" -i "${FILES[$i]}" )
done

# Chaîne de filtres, appliquée identiquement à chaque clip pour les
# uniformiser AVANT la concaténation (même résolution, même fps, même format
# de pixels, mêmes pixels carrés) — sans quoi concat produit des sauts.
#
#   crop   : largeur = hauteur * 9/16, arrondie au nombre pair le plus proche
#            (yuv420p exige des dimensions paires). Hauteur intégralement
#            conservée, recadrage centré (x/y par défaut = centre).
#   scale  : mise à l'échelle en 1080x1920, filtre lanczos (net).
#   setsar : pixels carrés, pour que tous les clips s'alignent.
#   fps    : fréquence uniforme, duplication/suppression d'images si besoin.
#   format : espace colorimétrique uniforme.
FILTER=""
for i in "${!FILES[@]}"; do
  FILTER+="[${i}:v]crop=w=2*round(ih*9/32):h=ih,"
  FILTER+="scale=${OUT_W}:${OUT_H}:flags=lanczos,"
  FILTER+="setsar=1,fps=${FPS},format=${PIX_FMT}[v${i}];"
done
# Concaténation en coupes franches : concat enchaîne bout à bout, sans
# transition ni fondu. a=0 => aucune piste audio n'est prise en compte.
for i in "${!FILES[@]}"; do FILTER+="[v${i}]"; done
FILTER+="concat=n=${#FILES[@]}:v=1:a=0[outv]"

echo
echo "Encodage vers $OUT_PATH ..."
ffmpeg -hide_banner -loglevel warning -stats -y \
  "${INPUTS[@]}" \
  -filter_complex "$FILTER" \
  -map "[outv]" \
  -an \
  -c:v libx264 -preset "$PRESET" -crf "$CRF" \
  -pix_fmt "$PIX_FMT" \
  -r "$FPS" \
  -movflags +faststart \
  "$OUT_PATH"

# ──────────────────────────── CONTRÔLE ───────────────────────────────

echo
echo "─── ffprobe : $OUT_NAME ───"
read -r W H RATE DUR_OUT < <(
  ffprobe -v error -select_streams v:0 \
    -show_entries stream=width,height,r_frame_rate \
    -show_entries format=duration \
    -of default=nw=1:nk=1 "$OUT_PATH" | paste -sd' ' -
)
printf 'Durée      : %.2f s\n' "$DUR_OUT"
printf 'Dimensions : %sx%s\n' "$W" "$H"
printf 'Fréquence  : %s fps\n' "$(echo "$RATE" | awk -F/ '{printf "%g", $1/$2}')"
printf 'Audio      : %s\n' \
  "$(ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$OUT_PATH" | grep -q . && echo 'présent (INATTENDU)' || echo 'aucun')"

# Comparaison aux valeurs attendues, déduites de la configuration.
STATUS=0
check() { # libellé, obtenu, attendu
  if [[ "$2" == "$3" ]]; then printf '  OK   %-12s %s\n' "$1" "$2"
  else printf '  ÉCHEC %-12s %s (attendu %s)\n' "$1" "$2" "$3"; STATUS=1; fi
}
echo "Vérification :"
check "durée"      "$(printf '%.0f' "$DUR_OUT")" "$TOTAL"
check "largeur"    "$W"    "$OUT_W"
check "hauteur"    "$H"    "$OUT_H"
check "fps"        "$(echo "$RATE" | awk -F/ '{printf "%g", $1/$2}')" "$FPS"

echo
if [[ $STATUS -eq 0 ]]; then echo "Terminé : $OUT_PATH"
else echo "Terminé AVEC ÉCARTS : $OUT_PATH" >&2; fi
exit $STATUS

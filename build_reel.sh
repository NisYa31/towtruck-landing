#!/usr/bin/env bash
#
# build_reel.sh — Montage vertical prêt pour Instagram Reels.
#
# Assemble une liste de clips (coupes franches, sans transition) en une seule
# vidéo verticale H.264, avec un fondu de sortie sur la toute fin.
#
# Usage :
#   ./build_reel.sh                    # utilise VIDEO_DIR ci-dessous
#   ./build_reel.sh /chemin/vers/clips # dossier passé en argument
#   OUTPUT_NAME=urus_v2.mp4 ./build_reel.sh
#
set -euo pipefail

# Force le point comme séparateur décimal. Sous une locale française,
# awk formaterait "19,500" au lieu de "19.500", que ffmpeg rejette.
export LC_ALL=C

# ══════════════════════════════════════════════════════════════════════
#  CONFIGURATION — tout ce qui se modifie au quotidien est ici
# ══════════════════════════════════════════════════════════════════════

# Dossier contenant les clips sources (et où sera écrit le rendu).
VIDEO_DIR="${1:-${VIDEO_DIR:-Video-urus}}"

# Nom du fichier de sortie.
OUTPUT_NAME="${OUTPUT_NAME:-urus_v1.mp4}"

# Montage : un clip par ligne.
#   <horodatage>  <début>  <fin>   # commentaire libre
# - horodatage : les 6 chiffres du nom de fichier (hf_AAAAMMJJ_XXXXXX_....mp4)
# - début/fin  : secondes depuis le DÉBUT du fichier source (point décimal, pas
#                de virgule : 2.5 et non 2,5)
# Pour réordonner le montage, il suffit de déplacer les lignes.
CLIPS=(
  "192809   0   2.5   # ouverture, hero"
  "194405   0   5     # désert, mouvement"
  "193836   0   2     # parking, respiration"
  "194945   0   2     # poste de conduite"
  "201411   0   2     # banquette arrière fermée"
  "201929   0   2     # banquette arrière ouverte"
  "200403   0   5     # 3/4 arrière, plan final"
)

# Format de sortie.
WIDTH=1076
HEIGHT=1928
# Mettre FPS à la cadence native des sources évite la duplication d'images
# (une source en 24 fps rendue en 30 fps duplique une image sur quatre).
FPS=30

# Fondu de sortie, en secondes, appliqué à la fin du montage global.
# Mettre 0 pour aucun fondu. (Aucune transition entre les clips : coupe franche.)
FADE_OUT=1

# Encodage H.264. CRF plus bas = meilleure qualité / fichier plus lourd.
CRF=18
PRESET=slow

# Piste audio : 1 = ajoute une piste AAC muette (les plateformes la préfèrent),
# 0 = vidéo sans aucune piste audio.
SILENT_AUDIO=1

# ══════════════════════════════════════════════════════════════════════
#  MOTEUR — normalement rien à toucher en dessous
# ══════════════════════════════════════════════════════════════════════

die() { printf '\033[31merreur :\033[0m %s\n' "$*" >&2; exit 1; }
info() { printf '\033[36m•\033[0m %s\n' "$*"; }

command -v ffmpeg  >/dev/null || die "ffmpeg introuvable dans le PATH."
command -v ffprobe >/dev/null || die "ffprobe introuvable dans le PATH."
[[ -d $VIDEO_DIR ]] || die "dossier introuvable : $VIDEO_DIR"

OUTPUT="$VIDEO_DIR/$OUTPUT_NAME"

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
    awk -v d="$src_dur" -v e="$end" 'BEGIN { exit !(d + 0.05 < e) }' \
        && die "$(basename "$file") dure ${src_dur}s, or le montage demande jusqu'à ${end}s."

    seg=$(awk -v a="$start" -v b="$end" 'BEGIN { printf "%.3f", b - a }')
    total=$(awk -v t="$total" -v s="$seg" 'BEGIN { printf "%.3f", t + s }')

    info "$(printf '%d.' $((idx + 1))) $(basename "$file") — ${start}s → ${end}s (${seg}s)"

    inputs+=(-i "$file")
    # trim  : garde l'intervalle demandé      setpts : remet le clip à t=0
    # fps   : cadence uniforme                scale/pad : sécurité si un clip
    #                                         n'est pas déjà en WIDTHxHEIGHT
    filters+=(
        "[${idx}:v]trim=start=${start}:end=${end},setpts=PTS-STARTPTS,fps=${FPS},\
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

# Fondu de sortie sur la fin du montage global.
if awk -v f="$FADE_OUT" 'BEGIN { exit !(f > 0) }'; then
    fade_st=$(awk -v t="$total" -v f="$FADE_OUT" 'BEGIN { printf "%.3f", (t - f > 0 ? t - f : 0) }')
    graph+=";[vcat]fade=t=out:st=${fade_st}:d=${FADE_OUT}[vout]"
    info "fondu de sortie : ${FADE_OUT}s à partir de ${fade_st}s"
else
    graph+=";[vcat]null[vout]"
fi

audio_args=(-an)
if (( SILENT_AUDIO == 1 )); then
    inputs+=(-f lavfi -t "$total" -i anullsrc=channel_layout=stereo:sample_rate=48000)
    audio_args=(-map "${idx}:a" -c:a aac -b:a 128k)
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

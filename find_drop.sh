#!/usr/bin/env bash
#
# find_drop.sh — Trouve les temps forts d'un morceau et calcule le MUSIC_START
# à mettre dans build_reel.sh pour qu'un temps fort tombe sur une coupe.
#
# Usage :
#   ./find_drop.sh morceau.mp3        # cale sur la coupe à 2.5s
#   ./find_drop.sh morceau.mp3 7.5    # cale sur une autre coupe
#
# Coupes du montage : 2.5 / 7.5 / 9.5 / 11.5 / 13.5 / 15.5
#
set -euo pipefail
export LC_ALL=C

TRACK="${1:-}"
CUT="${2:-2.5}"
MONTAGE=20.5

[[ -n $TRACK && -f $TRACK ]] || { echo "usage : $0 <morceau.mp3> [seconde_de_coupe]" >&2; exit 1; }
command -v ffmpeg >/dev/null || { echo "ffmpeg introuvable" >&2; exit 1; }

dur=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$TRACK")
printf 'Morceau : %s (%.1fs)\n' "$(basename "$TRACK")" "$dur"

if awk -v d="$dur" -v m="$MONTAGE" 'BEGIN { exit !(d + 0.05 < m) }'; then
    printf '\033[31mAttention :\033[0m ce morceau est plus court que le montage (%.1fs < %ss).\n' "$dur" "$MONTAGE"
    printf 'build_reel.sh le refusera. Prends un morceau plus long.\n\n'
else
    printf '\n'
fi

# Loudness court terme (fenêtre glissante de 3s), échantillonné dans le temps.
prof=$(ffmpeg -hide_banner -nostats -i "$TRACK" \
        -af "ebur128=framelog=quiet:metadata=1,ametadata=print:key=lavfi.r128.S:file=-" \
        -f null - 2>/dev/null \
      | awk '/pts_time:/ { match($0, /pts_time:[0-9.]+/)
                           t = substr($0, RSTART + 9, RLENGTH - 9) }
             /r128\.S=/  { split($0, a, "=")
                           if (a[2] > -70) printf "%.2f %.2f\n", t, a[2] }')

[[ -n $prof ]] || { echo "impossible d'analyser ce fichier — est-ce bien un audio ?" >&2; exit 1; }

echo "$prof" | awk -v montage="$MONTAGE" -v total="$dur" -v cut="$CUT" '
  { t[NR] = $1; s[NR] = $2 }
  END {
    n = NR
    # Une montée nette dénergie sur ~2s est la signature dun drop.
    for (i = 1; i <= n; i++) {
      j = i
      while (j > 1 && t[i] - t[j] < 2.0) j--
      if (j == i) continue
      if (t[i] + montage > total) continue     # pas assez de morceau après
      d = s[i] - s[j]
      # On retient t[j], le debut de la montee : la fenetre glissante de 3s
      # fait que t[i] arrive apres coup.
      if (d > 2.0) { c++; cand[c] = t[j]; delta[c] = d }
    }
    # Tri décroissant par ampleur de montée.
    for (k = 1; k <= c; k++)
      for (l = k + 1; l <= c; l++)
        if (delta[l] > delta[k]) {
          x = delta[k]; delta[k] = delta[l]; delta[l] = x
          y = cand[k];  cand[k]  = cand[l];  cand[l]  = y
        }
    print "Temps forts détectés :"
    shown = 0
    for (k = 1; k <= c && shown < 4; k++) {
      ok = 1
      for (m = 1; m <= shown; m++)
        if (cand[k] > keep[m] - 5 && cand[k] < keep[m] + 5) ok = 0
      if (!ok) continue
      keep[++shown] = cand[k]
      printf "  %6.1fs   (+%.1f dB)\n", cand[k], delta[k]
    }
    if (shown == 0) {
      print "  aucune montée nette — morceau à énergie constante."
      print "\nCe type de morceau se cale librement : garde MUSIC_START=0."
      exit
    }
    printf "\nÀ reporter dans build_reel.sh :\n"
    for (m = 1; m <= shown; m++) {
      st = keep[m] - cut
      if (st < 0) st = 0
      printf "  MUSIC_START=%-6.1f  le temps fort de %.1fs tombera sur la coupe à %ss\n", st, keep[m], cut
    }
  }'

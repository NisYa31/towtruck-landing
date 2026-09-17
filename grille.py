#!/usr/bin/env python3
"""grille.py — Calcule la grille de montage calée sur les temps de la musique.

    ./grille.py <bpm> <images_par_clip_source> [temps_du_plan ...]
    ./grille.py 88.4 121                 # plan par défaut : 4 8 3 3 3 3 8
    ./grille.py 88.4 121 4 8 4 4 8       # 5 plans

Les positions de coupe sont calculées en temps CUMULÉS et chaque coupe est
arrondie à l'image la plus proche. Arrondir les durées une par une ferait
accumuler l'erreur.

Le script refuse toute grille qui demande à un plan plus d'images que le clip
source n'en contient : c'est le piège qui rend le montage inconstruisible et
ne se voit qu'au moment de lancer ffmpeg.
"""
import sys

FPS = 24
DEFAUT = [4, 8, 3, 3, 3, 3, 8]


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    bpm = float(sys.argv[1])
    src = int(sys.argv[2])
    plan = [int(x) for x in sys.argv[3:]] or DEFAUT

    beat = 60.0 / bpm
    total_b = sum(plan)
    print(f"\n  tempo {bpm:.2f} BPM → un temps = {beat:.4f} s")
    print(f"  clip source : {src} images ({src / FPS:.4f} s) → plan maximum "
          f"{src / FPS / beat:.2f} temps")
    print(f"  plan : {' / '.join(map(str, plan))} = {total_b} temps "
          f"= {total_b / 4:.2f} mesures", end="")
    if total_b % 4:
        print(f"   ⚠  pas un multiple de 4 : le montage ne finit pas sur une mesure")
    else:
        print()

    print(f"\n  {'plan':>4}  {'temps':>5}  {'images':>6}  {'durée':>8}  "
          f"{'coupe à':>9}  {'temps idéal':>11}  {'écart':>7}")
    print("  " + "─" * 62)

    cum_b = cum_f = 0
    pire = 0.0
    lignes, erreurs = [], []
    for i, b in enumerate(plan, 1):
        cum_b += b
        cut_f = round(cum_b * beat * FPS)
        nf = cut_f - cum_f
        ideal = cum_b * beat
        reel = cut_f / FPS
        ecart = abs(reel - ideal) * 1000
        pire = max(pire, ecart)
        if nf > src:
            erreurs.append(f"plan {i} : {nf} images demandées, {src} disponibles "
                           f"(dépasse de {nf - src})")
        print(f"  {i:>4}  {b:>5}  {nf:>6}  {nf / FPS:>7.4f}s  {reel:>8.4f}s  "
              f"{ideal:>10.4f}s  {ecart:>6.1f}ms")
        lignes.append(f'  "<horodatage>   0   {nf / FPS:.4f}   '
                      f'# plan {i} — {nf} images, {b} temps"')
        cum_f = cut_f

    print("  " + "─" * 62)
    print(f"  total : {cum_f} images = {cum_f / FPS:.4f} s   "
          f"écart maximum {pire:.1f} ms (une image en dure {1000 / FPS:.1f})")
    if pire > 150:
        print(f"  ⚠  au-delà de 150 ms l'écart s'entend.")

    if erreurs:
        print("\n  ✗ GRILLE INCONSTRUISIBLE :")
        for e in erreurs:
            print(f"      {e}")
        print("      Raccourcir les plans concernés ou changer de tempo.")
        sys.exit(1)

    print(f"\n  Bloc CLIPS à recopier dans build_reel.sh :\n")
    print("CLIPS=(")
    print("\n".join(lignes))
    print(")\n")


if __name__ == "__main__":
    main()

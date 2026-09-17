#!/usr/bin/env python3
"""cale_drops.py — Place les coupes du montage sur les vrais accents du morceau.

    ./cale_drops.py <musique> <bpm> <depart|auto> <nb_plans> [images_par_clip]

« auto » balaie tout le morceau et retient la fenêtre dont les coupes tombent
sur les accents les plus francs — c'est presque toujours meilleur qu'un départ
choisi à la main, parce qu'un temps fort isolé ne sert à rien si les dix
secondes qui suivent sont molles.

Au lieu d'imposer une structure rythmique arbitraire (4/8/3/3...), on mesure
où sont les accents dans l'extrait qui sera réellement utilisé, puis on choisit
les coupes parmi les temps les plus marqués.

Trois étapes :
  1. PHASE — le tempo seul ne dit pas OÙ tombe le premier temps. On corrèle
     l'enveloppe de flux spectral avec un peigne au tempo mesuré, et on retient
     le décalage qui maximise la somme.
  2. FORCE — chaque temps reçoit la force de l'accent qui lui correspond.
  3. DÉCOUPE — programmation dynamique : on choisit les coupes qui maximisent
     la force totale, sous contrainte de longueur de plan (le clip source ne
     contient qu'un nombre fini d'images) et de total en mesures entières.
"""
import subprocess, sys, numpy as np

SR, HOP, FPS = 22050, 128, 24


def pcm(path):
    out = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-ac", "1",
                          "-ar", str(SR), "-f", "f32le", "-"], capture_output=True)
    if out.returncode:
        sys.exit(out.stderr.decode()[:300])
    return np.frombuffer(out.stdout, dtype=np.float32)


def flux(x):
    n = len(x) // HOP * HOP
    env = np.sqrt(np.mean(x[:n].reshape(-1, HOP) ** 2, axis=1))
    f = np.diff(env)
    f[f < 0] = 0
    return f


def decoupe(forces, nplans, nbeats, maxi):
    """Programmation dynamique : les coupes qui maximisent la force totale."""
    MIN, NEG = 2, -1e18
    dp = np.full((nplans + 1, nbeats + 1), NEG)
    prev = np.zeros((nplans + 1, nbeats + 1), dtype=int)
    dp[0][0] = 0.0
    for p in range(1, nplans + 1):
        for b in range(1, nbeats + 1):
            for L in range(MIN, maxi + 1):
                if b - L < 0 or dp[p - 1][b - L] == NEG:
                    continue
                g = dp[p - 1][b - L] + forces[b]
                if g > dp[p][b]:
                    dp[p][b], prev[p][b] = g, L
    if dp[nplans][nbeats] == NEG:
        return None, None
    longueurs, b = [], nbeats
    for p in range(nplans, 0, -1):
        L = prev[p][b]
        longueurs.append(L)
        b -= L
    longueurs.reverse()
    return dp[nplans][nbeats], longueurs


def main():
    if len(sys.argv) < 5:
        sys.exit(__doc__)
    path, bpm, arg_dep, nplans = sys.argv[1], float(sys.argv[2]), sys.argv[3], int(sys.argv[4])
    src = int(sys.argv[5]) if len(sys.argv) > 5 else 121

    x = pcm(path)
    f = flux(x)
    fps_env = SR / HOP
    beat = 60.0 / bpm
    per = beat * fps_env
    duree = len(x) / SR

    # ── 1. phase ──────────────────────────────────────────────────────
    meilleur, phase = -1.0, 0.0
    for ph in np.arange(0, per, 0.25):
        idx = np.round(np.arange(ph, len(f) - 1, per)).astype(int)
        s_ = f[idx].sum()
        if s_ > meilleur:
            meilleur, phase = s_, ph
    t0 = phase / fps_env
    print(f"\n  tempo {bpm:.2f} BPM → un temps = {beat:.4f} s")
    print(f"  phase mesurée : premier temps à {t0:.4f} s du début du fichier")

    maxi = int(src / FPS / beat)
    nbeats = int(round(nplans * 3.2 / 4) * 4)
    nbeats = max(nbeats, nplans * 2)
    while nbeats > nplans * maxi:
        nbeats -= 4

    def force(t):
        i = int(t * fps_env)
        w = f[max(0, i - 3): i + 4]
        return float(w.max()) if len(w) else 0.0

    fmax = f.max() or 1.0

    def evalue(k0):
        """Force des coupes pour une fenêtre démarrant au temps n° k0."""
        temps = [t0 + (k0 + i) * beat for i in range(nbeats + 1)]
        if temps[-1] > duree:
            return None
        forces = np.array([force(t) for t in temps]) / fmax
        sc, lg = decoupe(forces, nplans, nbeats, maxi)
        if lg is None:
            return None
        # moyenne de la force des 10 coupes réellement retenues
        cuts, b = [], 0
        for L in lg:
            b += L
            cuts.append(forces[b])
        return float(np.mean(cuts)), float(np.min(cuts)), lg, temps[0], cuts

    # ── 2. fenêtre ────────────────────────────────────────────────────
    if arg_dep.lower() == "auto":
        kmax = int((duree - nbeats * beat - t0) / beat)
        essais = []
        for k0 in range(0, max(kmax, 1)):
            r = evalue(k0)
            if r:
                # on privilégie la coupe la plus faible : une seule coupe molle
                # se voit plus qu'une moyenne légèrement inférieure.
                essais.append((r[0] + 2 * r[1], k0, r))
        if not essais:
            sys.exit("  aucune fenêtre exploitable")
        essais.sort(reverse=True)
        print(f"  balayage : {len(essais)} fenêtres possibles")
        print(f"\n  {'départ':>9} {'accent moyen':>13} {'coupe la plus faible':>21}")
        print("  " + "─" * 46)
        for _, k0, r in essais[:5]:
            print(f"  {r[3]:>8.3f}s {r[0] * 100:>12.0f}% {r[1] * 100:>20.0f}%")
        _, k0, r = essais[0]
    else:
        k0 = int(np.ceil((float(arg_dep) - t0) / beat))
        r = evalue(k0)
        if not r:
            sys.exit("  fenêtre inexploitable à ce départ")

    moy, mini, longueurs, depart, cuts = r

    # ── 3. résultat ───────────────────────────────────────────────────
    print(f"\n  extrait retenu : départ {depart:.4f} s, {nbeats} temps "
          f"= {nbeats // 4} mesures = {nbeats * beat:.3f} s")
    print(f"  plan maximum : {maxi} temps ({maxi * beat:.3f} s, {src} images)")
    print(f"  structure : {'/'.join(map(str, longueurs))} = {sum(longueurs)} temps")
    print(f"\n  {'plan':>4} {'temps':>5} {'images':>6} {'durée':>8} "
          f"{'coupe à':>9} {'accent':>7}")
    print("  " + "─" * 48)
    cum_b = cum_f = 0
    lignes = []
    for i, L in enumerate(longueurs, 1):
        cum_b += L
        cut_f = round(cum_b * beat * FPS)
        nf = cut_f - cum_f
        assert nf <= src, f"plan {i} : {nf} images > {src}"
        pc = cuts[i - 1] * 100
        print(f"  {i:>4} {L:>5} {nf:>6} {nf / FPS:>7.4f}s {cut_f / FPS:>8.4f}s "
              f"{pc:>6.0f}% {'█' * int(pc / 12)}")
        lignes.append((nf, L))
        cum_f = cut_f
    print("  " + "─" * 48)
    print(f"  total : {cum_f} images = {cum_f / FPS:.4f} s   "
          f"accent moyen {moy * 100:.0f} %, plus faible {mini * 100:.0f} %")
    print(f"\nMUSIC_START={depart:.4f}\n")
    print("CLIPS=(")
    for i, (nf, L) in enumerate(lignes, 1):
        print(f'  "<horodatage>   0   {nf / FPS:.4f}   # plan {i} — {nf} images, {L} temps"')
    print(")\n")


if __name__ == "__main__":
    main()

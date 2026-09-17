#!/usr/bin/env python3
"""tempo.py — Analyse un morceau : tempo, dynamique, équilibre spectral.

    ./tempo.py musique.mp3

Le tempo est mesuré par un PEIGNE DE DIRAC appliqué au spectre de l'enveloppe
de flux spectral, sur toute la durée du morceau. L'autocorrélation de
l'enveloppe d'énergie, elle, donne des résultats faux : sur le morceau de
l'Urus elle annonçait 94 puis 96.38 BPM, deux fois à côté.

Un bon tempo donne un pic NET. Si aucun candidat ne se détache, le script
le dit : il ne faut alors pas se fier au chiffre.
"""
import subprocess, sys, numpy as np

SR, HOP = 22050, 128


def pcm(path, extra=()):
    """Décode en mono float32 22 kHz, avec filtres ffmpeg optionnels."""
    cmd = ["ffmpeg", "-v", "error", "-i", path, *extra,
           "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"]
    out = subprocess.run(cmd, capture_output=True)
    if out.returncode != 0:
        sys.exit(f"ffmpeg : {out.stderr.decode()[:400]}")
    return np.frombuffer(out.stdout, dtype=np.float32)


def flux_envelope(x):
    n = len(x) // HOP * HOP
    env = np.sqrt(np.mean(x[:n].reshape(-1, HOP) ** 2, axis=1))
    flux = np.diff(env)
    flux[flux < 0] = 0
    return flux - flux.mean()


def tempo(x):
    flux = flux_envelope(x)
    fps = SR / HOP
    F = np.fft.rfft(flux * np.hanning(len(flux)))
    freqs = np.fft.rfftfreq(len(flux), 1 / fps)
    mag = np.abs(F)

    def comb(bpm):
        f0 = bpm / 60.0
        return sum(mag[np.argmin(np.abs(freqs - f0 * h))] / h for h in (1, 2, 4, 8))

    grid = np.arange(60, 180, 0.01)
    sc = np.array([comb(b) for b in grid])

    def local_max(around, demi_largeur=1.5):
        """Meilleur score dans une fenêtre de +/- demi_largeur BPM."""
        m = (grid > around - demi_largeur) & (grid < around + demi_largeur)
        if not m.any():
            return None, 0.0
        i = np.flatnonzero(m)[sc[m].argmax()]
        return grid[i], sc[i]

    best = grid[sc.argmax()]

    # ── Correction d'octave ───────────────────────────────────────────
    # Le peigne surestime systématiquement le tempo d'un facteur 2 : trois
    # des quatre dents du double tombent sur de vraies harmoniques, et sa
    # première dent reçoit le poids 1 au lieu de 1/2. Sur un métronome de
    # référence à 88.40 BPM, la méthode brute répond 176.78.
    # Le double d'un tempo ne peut pas être « plus vrai » que le tempo :
    # à score comparable on redescend toujours d'une octave.
    SEUIL = 0.85
    octave = []
    while True:
        moitie, s_moitie = local_max(best / 2)
        if moitie is None or moitie < grid[0] or s_moitie < SEUIL * comb(best):
            break
        octave.append((best, moitie, s_moitie / comb(best)))
        best = moitie

    # Candidats = maxima locaux séparés d'au moins 1 BPM.
    top = sc.max()
    order = np.argsort(sc)[::-1]
    peaks, seen = [], []
    for i in order:
        if all(abs(grid[i] - g) > 1.0 for g in seen):
            peaks.append((grid[i], sc[i]))
            seen.append(grid[i])
        if len(peaks) == 5:
            break
    return best, peaks, top, octave


def loudness(path, prefiltre=""):
    """Niveau intégré et LRA. « prefiltre » est CHAÎNÉ à ebur128 et non passé
    dans un second -af : ffmpeg ne garde que le dernier -af, si bien qu'une
    seconde option annulerait silencieusement la première."""
    chaine = (prefiltre + "," if prefiltre else "") + "ebur128=peak=true"
    cmd = ["ffmpeg", "-nostats", "-i", path, "-af", chaine, "-f", "null", "-"]
    err = subprocess.run(cmd, capture_output=True).stderr.decode()
    grab = lambda k: next((l.split(":")[1].strip()
                           for l in err.splitlines() if l.strip().startswith(k + ":")), "?")
    return grab("I"), grab("LRA")


def spectrum(x):
    n = min(len(x), SR * 120)          # 2 minutes suffisent
    X = np.abs(np.fft.rfft(x[:n] * np.hanning(n)))
    f = np.fft.rfftfreq(n, 1 / SR)
    p = X ** 2
    low = p[f < 250].sum() / p.sum() * 100
    centroid = (f * p).sum() / p.sum()
    return low, centroid


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = sys.argv[1]
    x = pcm(path)
    dur = len(x) / SR
    print(f"\n  fichier         {path}")
    print(f"  durée           {dur:.1f} s ({int(dur // 60)} min {dur % 60:04.1f} s)")

    best, peaks, top, octave = tempo(x)
    print(f"\n  ── TEMPO (peigne de Dirac sur le flux spectral) ──")
    print(f"  tempo mesuré    {best:.2f} BPM   → un temps = {60 / best:.4f} s")
    print(f"  candidats :")
    for b, s in peaks:
        print(f"      {b:7.2f} BPM   score {s / top * 100:5.1f} %"
              + ("   ← retenu" if b == best else ""))
    for avant, apres, ratio in octave:
        print(f"  correction d'octave : {avant:.2f} → {apres:.2f} BPM "
              f"(le demi-tempo garde {ratio * 100:.0f} % du score)")

    # Un rival qui n'est ni une octave ni un multiple simple du tempo retenu
    # est le seul cas où le doute est réel.
    def parent(b):
        r = max(b, best) / min(b, best)
        return any(abs(r - k) < 0.04 for k in (1, 2, 3, 4, 1.5))
    rivaux = [(b, s) for b, s in peaks if not parent(b) and s / top > 0.70]
    if rivaux:
        print(f"\n  ⚠  {rivaux[0][0]:.2f} BPM atteint {rivaux[0][1] / top * 100:.0f} % "
              f"du score et n'est pas un multiple de {best:.2f} :")
        print(f"     aucun tempo ne se détache franchement. NE PAS s'y fier,")
        print(f"     recompter à l'oreille ou changer de morceau.")

    I, LRA = loudness(path)
    low, cen = spectrum(x)
    # Simulation d'un haut-parleur de téléphone : deux passes de coupe-bas.
    Ip, _ = loudness(path, "highpass=f=350:poles=2,highpass=f=350:poles=2")
    try:
        perte = float(I.split()[0]) - float(Ip.split()[0])
        perte_s = (f"perte de {perte:.1f} dB" if perte > 0
                   else f"gain de {-perte:.1f} dB")
    except ValueError:
        perte_s = "?"

    print(f"\n  ── DYNAMIQUE ET SPECTRE ──")
    print(f"  niveau intégré  {I}")
    print(f"  LRA             {LRA}"
          + ("   → dynamique nulle, le morceau fait tapis et non ressort"
             if _num(LRA) is not None and _num(LRA) < 4 else ""))
    print(f"  énergie < 250Hz {low:.1f} %"
          + ("   → très grave-dominant" if low > 80 else ""))
    print(f"  centroïde       {cen:.0f} Hz")
    print(f"  haut-parleur de téléphone : {perte_s} (deux passes highpass 350 Hz)")
    print()


def _num(s):
    try:
        return float(s.split()[0])
    except (ValueError, IndexError, AttributeError):
        return None


if __name__ == "__main__":
    main()

import numpy as np

from backend import audio_analyzer as aa


def test_energy_curve_always_returns_fixed_length():
    for n in (0, 1, 3, 16, 1000):
        curve = aa._energy_curve(np.linspace(0, 1, n) if n else np.array([]))
        assert len(curve) == aa.ENERGY_SEGMENTS
        assert all(np.isfinite(v) for v in curve)


def test_energy_curve_is_normalised_and_ordered():
    rms = np.linspace(0.1, 0.9, 320)  # 単調増加
    curve = aa._energy_curve(rms)

    assert min(curve) == 0.0
    assert max(curve) == 1.0
    assert all(b >= a for a, b in zip(curve, curve[1:]))


def test_energy_curve_of_constant_signal_is_neutral():
    assert aa._energy_curve(np.full(100, 0.4)) == [0.5] * aa.ENERGY_SEGMENTS


def test_short_signal_does_not_produce_nan():
    """rmsフレーム数が分割数より少なくても NaN を出さないこと。"""
    curve = aa._energy_curve(np.array([0.1, 0.9, 0.5]))
    assert len(curve) == aa.ENERGY_SEGMENTS
    assert not any(np.isnan(v) for v in curve)


def test_fallback_beats_matches_bpm():
    beats = aa._fallback_beats(duration=10.0, bpm=120.0)

    assert beats[0] == 0.0
    assert beats[-1] <= 10.0
    intervals = [round(b - a, 3) for a, b in zip(beats, beats[1:])]
    assert all(i == 0.5 for i in intervals)


def test_fallback_beats_handles_invalid_input():
    assert aa._fallback_beats(0, 120) == []
    assert aa._fallback_beats(10, 0) == []

import baseline

def test_hand_calculated_fixture():
    baseline.self_check()

def test_seeded_generation():
    assert baseline.generate(7, 40) == baseline.generate(7, 40)

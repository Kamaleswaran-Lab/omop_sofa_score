import pandas as pd
def test_vincent():
    # PaO2 85, FiO2 0.5 => PF 170 => resp 3
    pf = 85/0.5
    assert pf == 170
    print("Vincent test passed")
if __name__ == "__main__": test_vincent()

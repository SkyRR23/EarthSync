"""FAO-56 Example 28 reproduction, for numerical review only, never crop advice."""

from decimal import Decimal


def example28_kc(day):
    """Equation 66 with the published dry-bean example's four stage lengths."""
    if isinstance(day, bool) or not isinstance(day, int) or not 1 <= day <= 100:
        raise ValueError("Example 28 uses integer day indices 1..100")
    initial, mid, end = Decimal("0.15"), Decimal("1.19"), Decimal("0.35")
    if day <= 25:
        return initial
    if day <= 50:
        return initial + Decimal(day - 25) / 25 * (mid - initial)
    if day <= 80:
        return mid
    return mid + Decimal(day - 80) / 20 * (end - mid)

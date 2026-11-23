"""Compare decoded JSON at a harness evidence boundary."""


def json_matches(observed, expected):
    kind = type(expected)
    if kind in (int, float):
        # JSON has one number type, but Python bool is a subclass of int.
        return type(observed) in (int, float) and observed == expected
    if type(observed) is not kind:
        return False
    if kind is dict:
        return observed.keys() == expected.keys() and all(
            json_matches(observed[key], value) for key, value in expected.items())
    if kind is list:
        return len(observed) == len(expected) and all(
            json_matches(actual, wanted) for actual, wanted in zip(observed, expected))
    return kind in (bool, str, type(None)) and observed == expected


def require_json_match(observed, expected, boundary):
    """Raise before publishing or accepting a receipt for different data."""
    if not json_matches(observed, expected):
        raise RuntimeError(f'{boundary}: observed {observed!r}; expected {expected!r}')

"""Requirements on observed fixture evidence, including in optimized Python."""


def require(condition, message):
    if not condition:
        raise AssertionError(message)

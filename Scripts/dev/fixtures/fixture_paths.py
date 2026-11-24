"""Path admission for fixture-owned observations and artifact destinations."""


def require_owned_path(path, root, label):
    """Require a canonical strict descendant before any fixture I/O."""
    if (root != root.resolve() or path != path.resolve()
            or path == root or not path.is_relative_to(root)):
        raise ValueError(f'{label}: expected a canonical descendant of {root}, got {path}')

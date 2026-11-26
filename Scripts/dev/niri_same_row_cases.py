"""Scripted state/action pairs for the niri action-wire fixture."""

W, WS = 9007199254740993, 9007199254740992
A, B, C, D = 0, 1, 2, 3


def action(name, **args):
    return {name: args}


focus = action('FocusWindow', id=W)
down, up = action('MoveWindowDown'), action('MoveWindowUp')
left = action('ConsumeOrExpelWindowLeft', id=W)
right = action('ConsumeOrExpelWindowRight', id=W)
consume = action('ConsumeWindowIntoColumn')


def move(index):
    return action('MoveColumnToIndex', index=index)


def gap(anchor):
    return dict(kind='gap', workspaceId=str(WS), anchorId=None if anchor is None else str(anchor))


def stack(anchor, index):
    return dict(kind='stack', workspaceId=str(WS), anchorId=str(anchor), index=index)


def layout(columns, focused):
    return (columns, focused)


def case(initial, target, steps, observed, ok=True, delayed=False):
    columns, focused = observed
    position = next(([i, col.index(W) + 1] for i, col in enumerate(columns, 1) if W in col), [])
    return dict(initial=initial, steps=steps, delayed=delayed, qml=dict(windowId=str(W), target=target,
                result=[ok, not ok, dict(workspaceId=str(WS), posInScrollingLayout=position, focused=focused == W)]))


CASES = {
    'row-singleton-gap': case(layout([[A], [W], [B]], A), gap(B), [
        (focus, layout([[A], [W], [B]], W)), (move(3), layout([[A], [B], [W]], W)),
    ], layout([[A], [B], [W]], W)),
    'row-first-gap': case(layout([[A, W], [B]], W), gap(None), [
        (left, layout([[W], [A], [B]], W)),
    ], layout([[W], [A], [B]], W), delayed=True),
    'row-stacked-gap': case(layout([[A, W], [B], [C]], B), gap(C), [
        (right, layout([[A], [W], [B], [C]], B)),
        (focus, layout([[A], [W], [B], [C]], W)),
        (move(4), layout([[A], [B], [C], [W]], W)),
    ], layout([[A], [B], [C], [W]], W)),
    'row-reorder-down': case(layout([[A, W, B, C]], A), stack(A, 4), [
        (focus, layout([[A, W, B, C]], W)),
        (down, layout([[A, B, W, C]], W)), (down, layout([[A, B, C, W]], W)),
    ], layout([[A, B, C, W]], W)),
    'row-reorder-up': case(layout([[A, B, W]], W), stack(A, 1), [
        (up, layout([[A, W, B]], W)), (up, layout([[W, A, B]], W)),
    ], layout([[W, A, B]], W)),
    'row-adjacent-append': case(layout([[W], [A, B]], A), stack(A, 3), [
        (right, layout([[A, B, W]], A)), (focus, layout([[A, B, W]], W)),
    ], layout([[A, B, W]], W)),
    'row-active-target-append': case(layout([[A, B], [W, C]], B), stack(A, 3), [
        (consume, layout([[A, B, W], [C]], B)), (focus, layout([[A, B, W], [C]], W)),
    ], layout([[A, B, W], [C]], W)),
    'row-adjacent-stack': case(layout([[A], [B, W]], W), stack(A, 1), [
        (left, layout([[A], [W], [B]], W)),
        (left, layout([[A, W], [B]], W)), (up, layout([[W, A], [B]], W)),
    ], layout([[W, A], [B]], W)),
    'row-distant-singleton': case(layout([[A, B], [C], [W]], W), stack(A, 2), [
        (move(2), layout([[A, B], [W], [C]], W)),
        (left, layout([[A, B, W], [C]], W)), (up, layout([[A, W, B], [C]], W)),
    ], layout([[A, W, B], [C]], W)),
    'row-distant-stack': case(layout([[A, W], [B], [C, D]], B), stack(C, 1), [
        (right, layout([[A], [W], [B], [C, D]], B)),
        (focus, layout([[A], [W], [B], [C, D]], W)),
        (move(4), layout([[A], [B], [C, D], [W]], W)),
        (left, layout([[A], [B], [C, D, W]], W)),
        (up, layout([[A], [B], [C, W, D]], W)), (up, layout([[A], [B], [W, C, D]], W)),
    ], layout([[A], [B], [W, C, D]], W)),
    'row-noop-gap': case(layout([[A], [W], [B]], A), gap(A), [], layout([[A], [W], [B]], A)),
    'row-noop-stack': case(layout([[A, W, B]], A), stack(A, 2), [], layout([[A, W, B]], A)),
    'row-concurrent': case(layout([[A], [W], [B]], A), gap(B), [
        (focus, layout([[B], [W], [A]], W)),
    ], layout([[B], [W], [A]], W), ok=False),
    'row-error': case(layout([[A], [W], [B]], A), gap(B), [(focus, 'fixture rejection')],
                      layout([[A], [W], [B]], A), ok=False),
}

#!/usr/bin/env python3
"""Exercise the production zone builder with Node; assigned VM only."""
import os
from pathlib import Path
import subprocess
from workspace_guard import require_disk_backed_paths


CASES = r'''
const fs = require('fs'), vm = require('vm'), assert = require('assert');
const scope = {};
vm.createContext(scope);
vm.runInContext(fs.readFileSync(process.argv[1], 'utf8'), scope);
const screen = {name: 'A', x: 0, y: 0, width: 1000, height: 800};
const plain = value => JSON.parse(JSON.stringify(value));
function build(all=[screen], bar='top', dock=null, own=screen) {
    return plain(scope.zones(own, all, 8, bar, 40, dock));
}
function rect(edge, x, y, width, height, inner=false) { return {edge, inner, rect:{x,y,width,height}}; }
function simplify(zones) { return zones.map(({edge,inner,rect}) => ({edge,inner,rect})); }
function hit(zones,x,y) { return zones.filter(z => x>=z.rect.x && y>=z.rect.y && x<z.rect.x+z.rect.width && y<z.rect.y+z.rect.height); }
assert.deepStrictEqual(simplify(build()), [rect('left',0,40,1,752),rect('right',999,40,1,752),rect('top',8,0,984,1),rect('bottom',8,799,984,1)]);
console.log('PASS single monitor and bar-side corners');
for (const bar of ['top','bottom','left','right']) {
    const zones=build([screen],bar);
    for(const [x,y] of [[0,0],[999,0],[0,799],[999,799],[7,7],[992,792]]) assert.equal(hit(zones,x,y).length,0);
    assert.equal(zones.length,4);
    assert.equal(hit(zones,bar==='left'?0:999,bar==='top'?39:bar==='bottom'?760:400).length, bar==='top'||bar==='bottom'?0:1);
    for(const zone of zones) assert.ok(zone.rect.width>0 && zone.rect.height>0);
}
console.log('PASS all four bar positions and excluded corners');
const right={name:'B',x:1000,y:0,width:800,height:800};
assert.deepStrictEqual(simplify(build([screen,right])).filter(z=>z.edge==='right'),[rect('right',992,40,8,752,true)]);
const bottom={name:'B',x:0,y:800,width:1000,height:600};
assert.deepStrictEqual(simplify(build([screen,bottom])).filter(z=>z.edge==='bottom'),[rect('bottom',8,792,984,8,true)]);
const above={name:'B',x:0,y:-800,width:1000,height:800};
assert.deepStrictEqual(simplify(build([screen,above])).filter(z=>z.edge==='top'),[rect('top',8,0,984,8,true)]);
const left={name:'B',x:-1000,y:0,width:1000,height:800};
assert.deepStrictEqual(simplify(build([screen,left])).filter(z=>z.edge==='left'),[rect('left',0,40,8,752,true)]);
console.log('PASS side by side and stacked in all directions');
const partial={name:'B',x:1000,y:200,width:800,height:300};
assert.deepStrictEqual(simplify(build([screen,partial])).filter(z=>z.edge==='right'),[
    rect('right',999,40,1,160),rect('right',992,200,8,300,true),rect('right',999,500,1,292)]);
const disjoint={name:'C',x:1001,y:0,width:500,height:800};
assert.deepStrictEqual(build([screen,disjoint]),build());
const translated={...screen,x:-900,y:-100};
assert.deepStrictEqual(simplify(build([translated,{...partial,x:100,y:100}], 'top', null, translated)),simplify(build([screen,partial])));
console.log('PASS partial touch, gap and negative global origin');
for (const dock of [{x:400,y:799,width:200,height:1},{x:0,y:200,width:1,height:200},
                   {x:999,y:200,width:1,height:200},{x:400,y:0,width:200,height:1}]) {
    const zones=build([screen,right], 'top', dock);
    for(const z of zones) {
        const r=z.rect;
        assert.ok(r.x+r.width<=dock.x || dock.x+dock.width<=r.x || r.y+r.height<=dock.y || dock.y+dock.height<=r.y);
    }
    assert.equal(hit(zones,dock.x,dock.y).length,0);
}
assert.deepStrictEqual(plain(scope.subtractRect({x:0,y:0,width:8,height:100},{x:2,y:20,width:2,height:40})),[
 {x:0,y:0,width:8,height:20},{x:0,y:60,width:8,height:40},{x:0,y:20,width:2,height:40},{x:4,y:20,width:4,height:40}]);
console.log('PASS dock reveal subtraction on every edge, including inner strips');
assert.equal(scope.zones(screen,[screen],0,'top',40,null).length,0);
assert.ok(build().every(z => z.kind === 'edge'));
const ALL = ['topLeft','topRight','bottomLeft','bottomRight'];
assert.equal(hit(plain(scope.zones(screen,[screen],2,'top',0,null,[])),0,3).length,1,'empty corner retains edge');
assert.equal(hit(plain(scope.zones(screen,[screen],2,'top',0,null,['topLeft'])),0,3).length,0,'configured corner excludes edge');
assert.equal(hit(plain(scope.zones(screen,[screen],2,'top',0,null,['bottomRight'])),0,3).length,1,'other configured corner retains edge');
const corners = (own, names=ALL) => plain(scope.corners(own, names));
const cornerRect = (corner, x, y) => ({kind:'corner', corner, screenName:'A', rect:{x,y,width:5,height:5}, key:'A:corner:'+corner});
assert.deepStrictEqual(corners(screen), [cornerRect('topLeft',0,0), cornerRect('topRight',995,0),
    cornerRect('bottomLeft',0,795), cornerRect('bottomRight',995,795)]);
assert.deepStrictEqual(corners(screen, ['bottomRight','topLeft','unknown']).map(z => z.corner), ['topLeft','bottomRight']);
assert.deepStrictEqual(corners(screen, []), []);
assert.deepStrictEqual(corners({...screen, width:0}), []);
console.log('PASS four 5x5 corners on one output, configured subset only');
const globalRects = (own, zones) => zones.map(z => ({...z, global:{x:own.x+z.rect.x, y:own.y+z.rect.y, width:z.rect.width, height:z.rect.height}}));
const touchesOther = (own, others, rect) => others.some(o => {
    const g = {x:own.x+rect.x, y:own.y+rect.y, width:rect.width, height:rect.height};
    const xTouch = g.x === o.x + o.width || g.x + g.width === o.x;
    const yTouch = g.y === o.y + o.height || g.y + g.height === o.y;
    const xOverlap = g.x < o.x + o.width && o.x < g.x + g.width;
    const yOverlap = g.y < o.y + o.height && o.y < g.y + g.height;
    return (xTouch && yOverlap) || (yTouch && xOverlap);
});
const pairs = [[right, 'side by side'], [bottom, 'stacked'], [partial, 'partial touch']];
for (const [other, label] of pairs) {
    const ownCorners = corners(screen), otherCorners = plain(scope.corners(other, ALL));
    assert.equal(ownCorners.length + otherCorners.length, 8, label);
    for (const z of otherCorners) assert.equal(z.rect.width * z.rect.height, 25, label);
    const inner = ownCorners.filter(z => touchesOther(screen,[other],z.rect)).length
                + otherCorners.filter(z => touchesOther(other,[screen],z.rect)).length;
    if (label === 'side by side') {
        assert.equal(inner, 4, label);
        assert.deepStrictEqual(ownCorners.filter(z => touchesOther(screen,[other],z.rect)).map(z => z.corner), ['topRight','bottomRight']);
        assert.deepStrictEqual(otherCorners.filter(z => touchesOther(other,[screen],z.rect)).map(z => z.corner), ['topLeft','bottomLeft']);
    } else if (label === 'stacked') {
        assert.equal(inner, 4, label);
    } else {
        assert.equal(inner, 2, label); // only the partner's left corners touch A's right side
    }
    const keys = new Set(ownCorners.concat(otherCorners).map(z => z.key));
    assert.equal(keys.size, 8, label + ' keys unique');
}
console.log('PASS eight corners on two outputs: side by side (4 inner), stacked (4 inner), partial touch');
let disjointChecks = 0;
for (const all of [[screen], [screen,right], [screen,bottom], [screen,partial], [screen,left], [screen,above]]) {
    for (let frame = 4; frame <= 24; frame++) {
        for (const bar of ['top','bottom','left','right']) {
            for (const thickness of [0, frame, 24, 40]) {
                const edges = plain(scope.zones(screen, all, frame, bar, thickness, null, ALL));
                assert.ok(edges.length > 0, JSON.stringify({all, frame, bar, thickness, reason:'empty edge matrix'}));
                const cornerZones = corners(screen);
                for (const e of edges) {
                    for (const c of cornerZones) {
                        const r = e.rect, q = c.rect;
                        assert.ok(r.x+r.width<=q.x || q.x+q.width<=r.x || r.y+r.height<=q.y || q.y+q.height<=r.y,
                                  JSON.stringify({frame, bar, thickness, e, c}));
                        disjointChecks++;
                    }
                    for (const [x,y] of [[0,0],[999,0],[0,799],[999,799],[4,4],[995,795]])
                        assert.ok(!(x>=e.rect.x && y>=e.rect.y && x<e.rect.x+e.rect.width && y<e.rect.y+e.rect.height), 'corner pixel in edge');
                }
            }
        }
    }
}
assert.ok(disjointChecks > 1000);
const frame4 = simplify(plain(scope.zones(screen,[screen],4,'left',0,null,ALL)));
assert.deepStrictEqual(frame4.filter(z => z.edge === 'top'), [rect('top',5,0,990,1)]);
console.log('PASS corners and edges disjoint for frame 4-24, every bar position and thickness (' + disjointChecks + ' pairs)');
console.log('EDGE_SCROLL_ZONES: PASS');
'''


if __name__ == '__main__':
    require_disk_backed_paths(os.environ['TMPDIR'])
    source = Path(__file__).resolve().parents[2] / 'Helpers/EdgeZones.js'
    subprocess.run(['node', '-e', CASES, str(source)], check=True, timeout=90)

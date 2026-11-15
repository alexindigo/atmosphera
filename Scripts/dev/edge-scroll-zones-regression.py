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
console.log('EDGE_SCROLL_ZONES: PASS');
'''


if __name__ == '__main__':
    require_disk_backed_paths(os.environ['TMPDIR'])
    source = Path(__file__).resolve().parents[2] / 'Helpers/EdgeZones.js'
    subprocess.run(['node', '-e', CASES, str(source)], check=True, timeout=90)

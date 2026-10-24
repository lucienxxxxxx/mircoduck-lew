import fs from 'node:fs';
import assert from 'node:assert/strict';
const source = fs.readFileSync(new URL('../console/static/service-builds.js',import.meta.url),'utf8');
const {supportsFeature} = await import('data:text/javascript;base64,'+Buffer.from(source).toString('base64'));
const cases = [
  [{build:'1fa8438-feetech-control.43-ft01.1'},'supported',true],
  [{build:'1fa8438-feetech-ft6-control.43'},'supported',true],
  [{build:'unknown'},'supported',false],
  [{build:'1fa8438-feetech-control.43-ft01.1',management_capabilities:{supported:false}},'supported',false],
  [{build:'1fa8438-feetech-control.43-ft01.1'},'unknown_feature',false],
  [{build:'590b986-feetech-ft6-control.7'},'motion',false],
];
for(const [report,feature,expected] of cases) assert.equal(supportsFeature(report,feature),expected);
console.log('6 browser compatibility cases passed');

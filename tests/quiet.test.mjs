import test from 'node:test';import assert from 'node:assert/strict';import {AudioEngine} from '../dist/audio.js';
test('Quiet note preview never creates or resumes a hardware audio context',async()=>{const engine=new AudioEngine();engine.setSilent(true);await engine.previewNote('keys',60);assert.equal(engine.ctx,null);assert.equal(engine.active.size,0);assert.equal(engine.silent,true)});

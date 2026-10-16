import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {encodeMIDI,validateProject} from '../dist/music.js';
import {decodeMIDI} from '../dist/midi.js';
const read=name=>readFile(new URL('../examples/'+name,import.meta.url));
test('Actual simplified-UI download is byte-exact original: all notes sounds colors IDs source links and ranges stay unchanged',async()=>{
 const actual=await read('ui-simplified.sprout'),original=await read('shared-transform-original.sprout');assert.deepEqual(actual,original);
 const project=JSON.parse(actual);assert.deepEqual(validateProject(project),project);assert.equal(project.tracks.length,7);assert.equal(project.tracks.reduce((sum,t)=>sum+t.notes.length,0),816);
});
test('Actual simplified-UI MIDI remains the exact original performed export with 816 notes',async()=>{
 const project=JSON.parse(await read('ui-simplified.sprout')),midi=await read('ui-simplified.mid');assert.deepEqual(midi,Buffer.from(encodeMIDI(project)));
 const imported=decodeMIDI(midi);assert.equal(imported.report.importedNotes,816);
});

// One shared duration contract for files, generators, editors and adapters.
export const BAR_LENGTHS=[4,8,16,32,64];
export const MAX_BARS=64,MAX_BEATS=MAX_BARS*4,MAX_PROJECT_NOTES=12000;
export function validBars(bars){return Number.isInteger(bars)&&BAR_LENGTHS.includes(bars)}
export function expandedBars(end,current=4){const bars=BAR_LENGTHS.find(b=>b>=current&&b*4>=end-.00005);if(!bars)throw Error('超过 64 小节工程上限');return bars}

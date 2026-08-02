import assert from 'node:assert/strict'
import fs from 'node:fs/promises'
import { renderMermaidSVG } from 'beautiful-mermaid'

const fixtureUrl = new URL('../docs/guide/diagrams/semantic-label-escaping.mmd', import.meta.url)
const source = (await fs.readFile(fixtureUrl, 'utf8')).trimEnd()

assert.equal(source.split('\n').length, 4, 'semantic text introduced a Mermaid source line')
assert.equal((source.match(/ --> /g) ?? []).length, 3, 'semantic text introduced a transition')
assert.equal((source.match(/<br\/>/g) ?? []).length, 2, 'only renderer-owned layout breaks may survive')

const svg = renderMermaidSVG(source)
const visibleBase =
  'Command &quot;quote&quot; &#39;apostrophe&#39; ＜br＞ ＜br/＞ ＜br /＞ &amp;lt;br&amp;gt; | {value}␍␊＼n / Event'
const visibleGuard =
  'g: Command &quot;quote&quot; &#39;apostrophe&#39; ＜br＞ ＜br/＞ ＜br /＞ &amp;lt;br&amp;gt; | {value}␍␊＼n'

assert.equal((svg.match(/<polyline class="edge"/g) ?? []).length, 3, 'backend parsed an extra transition')
assert.equal((svg.match(/<tspan /g) ?? []).length, 3, 'backend parsed semantic text as extra layout')
assert.ok(svg.includes(`>${visibleBase}</tspan>`), 'backend did not preserve the exact escaped base label')
assert.ok(svg.includes('>u: (keep)</tspan>'), 'backend did not preserve the update line')
assert.ok(svg.includes(`>${visibleGuard}</tspan>`), 'backend did not preserve the exact escaped guard label')

console.log('Verified semantic-label escaping through beautiful-mermaid')
